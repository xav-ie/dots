import AppKit
import ApplicationServices
import Foundation

extension Daemon {
  // Query AX for the currently focused window of an app. Used by acceptOSFront
  // to seed logicalWid/lastWid from OS notifications (startup, manual focus, etc).
  func focusedWindowWid(_ pid: pid_t) -> CGWindowID? {
    let axApp = AXUIElementCreateApplication(pid)
    guard let el = axElement(axApp, kAXFocusedWindowAttribute as String) else { return nil }
    return axWindowID(el)
  }

  func activate(_ pid: pid_t) {
    recordFront(pid)
    setLogical(pid: pid, wid: nil)
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    scheduleAssertFront(pid)
  }

  func raiseWindow(_ el: AXUIElement, _ pid: pid_t) {
    AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
  }

  // If an earlier activation from the same burst commits after this one (OS
  // out-of-order commit), re-assert the correct final target.
  func scheduleAssertFront(_ pid: pid_t) {
    pendingAssert?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
        dbg("assertFront re-activate \(pid)")
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
      }
    }
    pendingAssert = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
  }

  func focus(_ w: AXWin) {
    lastWid[w.pid] = w.wid
    setLogical(pid: w.pid, wid: w.wid)
    recordFront(w.pid)
    raiseWindow(w.el, w.pid)
    scheduleAssertFront(w.pid)
  }

  // Real, cyclable windows of `pids` on the CURRENT Space, sorted by CGWindowID
  // (ascends with creation — stable cycle order that doesn't shift as z-order churns).
  // Drops Picture-in-Picture and minimized windows.
  //
  // kAXWindowsAttribute returns ALL windows for an app regardless of space. For
  // single-pid multi-window apps (Ghostty), that means windows from other spaces
  // bleed in and cause cycleAppWindows to take the wrong path. We cross-reference
  // against CGWindowListCreate(onScreenOnly) — which IS space-scoped — to filter
  // to only windows actually visible on the current space.
  func realWindows(_ pids: [pid_t]) -> [AXWin] {
    // Fetch the set of window IDs currently on-screen (current space only).
    // kCGWindowListOptionOnScreenOnly excludes off-space and minimized windows.
    let onScreenWids: Set<CGWindowID>
    let cgOpts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    if let info = CGWindowListCopyWindowInfo(cgOpts, kCGNullWindowID) as? [[String: Any]] {
      onScreenWids = Set(info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    } else {
      onScreenWids = []
    }

    var byWid: [CGWindowID: AXWin] = [:]
    func consider(_ el: AXUIElement, _ pid: pid_t) {
      guard let wid = axWindowID(el), byWid[wid] == nil else { return }
      guard onScreenWids.isEmpty || onScreenWids.contains(wid) else { return }
      let title = axString(el, kAXTitleAttribute as String) ?? ""
      if title == "Picture-in-Picture" { return }
      if axBool(el, kAXMinimizedAttribute as String) { return }
      byWid[wid] = AXWin(el: el, pid: pid, wid: wid, title: title)
    }
    for pid in pids {
      let axApp = AXUIElementCreateApplication(pid)
      var wv: CFTypeRef?
      if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wv) == .success,
        let wins = wv as? [AXUIElement]
      {
        for w in wins { consider(w, pid) }
      }
      if let f = axElement(axApp, kAXFocusedWindowAttribute as String) { consider(f, pid) }
    }
    return byWid.values.sorted { $0.wid < $1.wid }
  }

  func cycleAppWindows(_ pids: [pid_t]) {
    let here = realWindows(pids)
    // Check for off-space windows by comparing AX results against the yabai cache.
    // Checking by pid absence alone misses single-pid apps (e.g. Ghostty) that have
    // windows on multiple Spaces: the pid appears in `here` via its on-space window,
    // so a pid-only check would never detect the off-space sibling window.
    let hereWids = Set(here.map { Int($0.wid) })
    let cached = yabaiWindows(for: pids, in: winCache)
    let hasOffSpace = cached.contains { !hereWids.contains($0.id) }
    // Also use the cross-space path when the cache is cold (empty): there may be
    // off-space windows we don't know about yet. cycleCrossSpace will live-fetch.
    if hasOffSpace || winCache.isEmpty {
      cycleCrossSpace(pids, here: here)
      return
    }
    guard !here.isEmpty else {
      if let p = pids.min(by: { mruRank($0) < mruRank($1) }) { activate(p) }
      return
    }
    let curWid = (logicalPid.map { pids.contains($0) } ?? false) ? logicalWid : nil
    if let cur = curWid, let i = here.firstIndex(where: { $0.wid == cur }) {
      focus(here[(i + 1) % here.count])
    } else {
      focus(here[0])
    }
  }

  func cycleCrossSpace(_ pids: [pid_t], here: [AXWin]) {
    if crossSpaceBusy {
      dbg("DROP-busy crossSpace")
      return
    }
    crossSpaceBusy = true
    let cached = yabaiWindows(for: pids, in: winCache)
    // Cache is usable if it has at least one window not visible on the current Space.
    let hereWids = Set(here.map { Int($0.wid) })
    let covered = cached.contains { !hereWids.contains($0.id) }
    dbg("crossSpace covered=\(covered) cached=\(cached.map { $0.id })")
    if covered {
      performJump(cached, here: here)
      scheduleRefresh()
    } else {
      DispatchQueue.global(qos: .userInitiated).async {
        let full = fetchYabaiWindows()
        let live = self.yabaiWindows(for: pids, in: full)
        DispatchQueue.main.async {
          self.winCache = full
          self.performJump(live, here: here)
        }
      }
    }
  }

  func yabaiWindows(for pids: [pid_t], in list: [YWindow]) -> [YWindow] {
    list
      .filter { pids.contains(pid_t($0.pid)) && $0.title != "Picture-in-Picture" }
      .sorted { $0.id < $1.id }
  }

  func performJump(_ all: [YWindow], here: [AXWin]) {
    guard !all.isEmpty else {
      crossSpaceBusy = false
      return
    }
    let curId = logicalWid.map { Int($0) }
    let idx = curId.flatMap { c in all.firstIndex { $0.id == c } } ?? -1
    let next = all[(idx + 1) % all.count]
    let nextPid = pid_t(next.pid)
    if let w = here.first(where: { $0.wid == CGWindowID(next.id) }) {
      dbg("jump AX cur=\(curId ?? -1) next=\(next.id)")
      focus(w)
      crossSpaceBusy = false
    } else {
      dbg("jump window --focus \(next.id) space=\(next.space) cur=\(curId ?? -1)")
      jumpToSpace(next.space, pid: nextPid, wid: CGWindowID(next.id))
    }
  }

  // Focuses `wid` on its space via `yabai window --focus`, which switches space
  // AND focuses the specific window atomically. This avoids the flash that
  // `space --focus N` causes: with the space-only command, macOS briefly activates
  // the target space's previous frontmost app before our onSpaceChanged raise fires.
  // Using `window --focus` lets yabai set the focus BEFORE the visual transition,
  // so the correct window appears immediately.
  //
  // crossSpaceBusy is held until the yabai command returns, shielding acceptOSFront
  // from transient OS activations during the transition.
  func jumpToSpace(_ space: Int, pid: pid_t, wid: CGWindowID) {
    pendingAssert?.cancel()
    pendingAssert = nil
    crossSpaceBusy = true
    pendingWindowRaise = (pid: pid, wid: wid)
    lastWid[pid] = wid
    setLogical(pid: pid, wid: wid)
    recordFront(pid)
    DispatchQueue.global(qos: .userInitiated).async {
      let (st, _) = run(resolve(YABAI), ["-m", "window", "--focus", String(wid)])
      dbg("window --focus \(wid) (space \(space)) status=\(st)")
      DispatchQueue.main.async {
        self.crossSpaceBusy = false
      }
      // Safety net: if yabai's window --focus didn't raise the window (e.g. the
      // window moved spaces, or the space switch notification fires late), fall back
      // to our own AX raise after 300ms.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self = self, self.pendingWindowRaise?.wid == wid else { return }
        dbg("jumpToSpace safety-net wid=\(wid)")
        self.onSpaceChanged()
      }
    }
  }

  // Called by activeSpaceDidChangeNotification (main trigger) and by the 300ms
  // safety net. Raises the pending target window on the now-active space.
  func onSpaceChanged() {
    guard let raise = pendingWindowRaise else { return }
    pendingWindowRaise = nil
    crossSpaceBusy = false
    if let w = realWindows([raise.pid]).first(where: { $0.wid == raise.wid }) {
      raiseWindow(w.el, raise.pid)
    } else {
      NSRunningApplication(processIdentifier: raise.pid)?.activate(options: [])
    }
  }

  func scheduleRefresh() {
    if refreshScheduled { return }
    refreshScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      self.refreshScheduled = false
      DispatchQueue.global(qos: .utility).async {
        let w = fetchYabaiWindows()
        DispatchQueue.main.async { self.winCache = w }
      }
    }
  }

  func focusRealWindow(_ pid: pid_t) {
    let onSpace = realWindows([pid])
    let targetWid = lastWid[pid]
    let targetId = targetWid.map { Int($0) }

    // Target window is on this Space — focus it directly.
    if let wid = targetWid, let w = onSpace.first(where: { $0.wid == wid }) {
      dbg("focusReal AX pid=\(pid) wid=\(w.wid)")
      focus(w)
      return
    }
    // No target preference — any on-space window will do.
    if targetWid == nil, let w = onSpace.first {
      dbg("focusReal AX (any) pid=\(pid) wid=\(w.wid)")
      focus(w)
      return
    }
    // Target is off-space (or no on-space windows exist) — find it via yabai.
    // Do NOT fall back to an on-space window of the same pid: that would flash the
    // wrong window before drain corrects it.
    if let yw = yabaiWindows(for: [pid], in: winCache).first(where: {
      targetId == nil || $0.id == targetId!
    }) {
      dbg("focusReal space --focus \(yw.space) (cache) pid=\(pid)")
      jumpToSpace(yw.space, pid: pid, wid: CGWindowID(yw.id))
      scheduleRefresh()
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let full = fetchYabaiWindows()
      let yw = self.yabaiWindows(for: [pid], in: full).first {
        targetId == nil || $0.id == targetId!
      }
      dbg("focusReal live pid=\(pid) found=\(yw != nil) space=\(yw?.space ?? -1)")
      DispatchQueue.main.async {
        self.winCache = full
        if let yw {
          self.jumpToSpace(yw.space, pid: pid, wid: CGWindowID(yw.id))
        } else {
          self.activate(pid)
        }
      }
    }
  }
}
