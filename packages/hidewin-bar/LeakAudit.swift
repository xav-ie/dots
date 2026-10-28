// LeakAudit — while Screenshare Mode is on, check that what should be hidden
// really is.
//
// The dylib flips each window's sharingType, but the WindowServer can end up
// disagreeing with it: a window once stayed capturable (sharing state 1) while
// its app believed it was hidden, so every later HIDE was skipped as a no-op.
// The cause wasn't found, and only relaunching the app fixed it. So instead of
// trusting the flag, audit the outcome: every few seconds, read the
// WindowServer's own sharing state for on-screen windows of injected apps.
// A window that should be hidden but is capturable gets its app's hide
// re-asserted; if it's still capturable on the next pass, the bar icon turns
// red (the bar is excluded from capture, so only you see the warning).

import AppKit

private let AUDIT_INTERVAL: TimeInterval = 5
private var auditTimer: Timer?
private var reasserted = Set<pid_t>()  // re-hidden on the previous pass
var leakingPids = Set<pid_t>()  // still capturable after a re-assert

extension Controller {
  func startLeakAudit() {
    guard auditTimer == nil else { return }
    auditTimer = Timer.scheduledTimer(withTimeInterval: AUDIT_INTERVAL, repeats: true) {
      [weak self] _ in self?.auditLeaks()
    }
    auditTimer?.tolerance = 1
  }

  func stopLeakAudit() {
    auditTimer?.invalidate()
    auditTimer = nil
    reasserted.removeAll()
    if !leakingPids.isEmpty {
      leakingPids.removeAll()
      publishMode()
    }
  }

  // On-screen, normal-level windows of injected apps that the WindowServer
  // would still hand to a capturer, minus anything you revealed.
  private func capturableWindows() -> [pid_t: [Int]] {
    let list =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    var found = [pid_t: [Int]]()
    for w in list {
      guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, labels[pid] != nil,
        (w[kCGWindowLayer as String] as? Int) == 0,
        (w[kCGWindowSharingState as String] as? Int ?? 0) != 0,
        (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
        let number = w[kCGWindowNumber as String] as? Int,
        let b = w[kCGWindowBounds as String] as? [String: CGFloat],
        (b["Width"] ?? 0) >= 100, (b["Height"] ?? 0) >= 100,
        !revealed.contains(String(pid)), !revealed.contains("\(pid)#\(number)")
      else { continue }
      found[pid, default: []].append(number)
    }
    return found
  }

  private func auditLeaks() {
    guard screenshareMode else { return stopLeakAudit() }
    let leaking = capturableWindows()
    let stuck = Set(leaking.keys).intersection(reasserted)
    for pid in leaking.keys where !reasserted.contains(pid) {
      // A process-wide HIDE clears that app's per-window reveals; replay them.
      post(HIDE, String(pid))
      for target in revealed where target.hasPrefix("\(pid)#") { post(SHOW, target) }
    }
    reasserted = Set(leaking.keys)
    if stuck != leakingPids {
      leakingPids = stuck
      publishMode()
    }
  }
}
