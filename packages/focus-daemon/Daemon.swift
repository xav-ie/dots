import AppKit
import Foundation

final class Daemon {
  // Most-recently-activated pids, newest first. Maintained from NSWorkspace.
  var mru: [pid_t] = []

  // Logical focus state: what WE last commanded, updated synchronously before
  // any OS activate() call. Commands use this to decide the next window/app to
  // focus, rather than querying NSWorkspace.frontmostApplication which reflects
  // the WindowServer's committed state (may lag our commands by 50–200ms).
  var logicalPid: pid_t? = nil
  var logicalWid: CGWindowID? = nil
  var logicalUpdatedAt: Date = .distantPast

  // "Fire first, correct later" command queue.
  // The FIRST command in a burst executes immediately (zero latency). Subsequent
  // commands within DRAIN_IDLE are queued; when the burst settles drain() simulates
  // all commands from the burst-start logical state and fires an override if the
  // final target differs from where the first command landed.
  var commandQueue: [[String]] = []
  var drainToken = 0
  let DRAIN_IDLE: TimeInterval = 0.050
  // Logical state snapshot taken just before the first command in a burst fires.
  // The drain simulation starts from here so it sees the full intent of the burst.
  var burstStartPid: pid_t? = nil
  var burstStartWid: CGWindowID? = nil

  // True while a cross-Space jump is running async, so a fast double-tap can't
  // fire two competing `space --focus` calls. Touched only on the main queue.
  var crossSpaceBusy = false
  // yabai's window list (id/pid/space), kept warm off the hot path so a
  // cross-Space jump reads a window's Space from here instead of doing a live
  // query. Refreshed (debounced) on yabai window signals and after each jump;
  // a cold/stale cache falls back to a live query. Main-queue only.
  var winCache: [YWindow] = []
  var refreshScheduled = false

  // Cancellable deferred re-assertion — guards against OS out-of-order activation commits.
  var pendingAssert: DispatchWorkItem? = nil

  // Set while a cross-space jump is pending commit. Cleared by onSpaceChanged()
  // (or by the yabai block as a safety net) once the target space is active.
  var pendingWindowRaise: (pid: pid_t, wid: CGWindowID)? = nil

  // Last-focused window per pid. MRU tracks which app was most recent, but for
  // apps with multiple windows under one pid (e.g. Ghostty) we also need to know
  // which window within that app was last active so focusRealWindow returns to it.
  var lastWid: [pid_t: CGWindowID] = [:]

  func recordFront(_ pid: pid_t) {
    mru.removeAll { $0 == pid }
    mru.insert(pid, at: 0)
    if mru.count > 64 { mru.removeLast() }
  }

  func mruRank(_ pid: pid_t) -> Int {
    mru.firstIndex(of: pid) ?? Int.max
  }

  // Always called before any OS activation — keeps logical state ahead of the OS.
  func setLogical(pid: pid_t, wid: CGWindowID?) {
    logicalPid = pid
    logicalWid = wid
    logicalUpdatedAt = Date()
  }

  // NSWorkspace told us something is front. If it's echoing our own recent
  // activate (< 400ms), trust our logical state for the wid. If it's a
  // user-initiated change (mouse click, cmd+tab), reset logical state.
  func acceptOSFront(_ pid: pid_t) {
    let age = Date().timeIntervalSince(logicalUpdatedAt)
    if logicalPid == pid && age < 0.4 {
      // OS is confirming our own recent activate — leave logical wid intact
    } else if crossSpaceBusy {
      // A space jump we triggered is in progress. macOS transiently activates the
      // previous space's front app during the transition — ignore it entirely.
      // jumpToSpace will AX-raise the correct target window once it clears.
    } else {
      logicalPid = pid
      logicalUpdatedAt = Date()
      if let wid = focusedWindowWid(pid) {
        logicalWid = wid
        // Only persist to lastWid for deliberate user changes (age > 0.1s).
        // Rapid transitions (age ≤ 0.1) can be artifacts of our own commands.
        if age > 0.1 { lastWid[pid] = wid }
      } else {
        logicalWid = nil
      }
      if age > 0.1 {
        pendingAssert?.cancel()
        pendingAssert = nil
      }
    }
  }
}
