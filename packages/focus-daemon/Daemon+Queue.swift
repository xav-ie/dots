import AppKit
import Foundation

extension Daemon {
  func matchingPids(_ name: String) -> [pid_t] {
    let want = name.lowercased()
    return NSWorkspace.shared.runningApplications.filter { app in
      guard app.activationPolicy == .regular else { return false }
      let exe = app.executableURL?.lastPathComponent.lowercased()
      let loc = app.localizedName?.lowercased()
      return exe == want || loc == want
    }.map { $0.processIdentifier }
  }

  func launch(_ name: String) {
    run(resolve("open"), ["-a", name])
  }

  func executeCommand(_ appNames: [String]) {
    var procs: [(app: String, pid: pid_t)] = []
    var missing: [String] = []
    for name in appNames {
      let p = matchingPids(name)
      if p.isEmpty { missing.append(name) } else { for pid in p { procs.append((name, pid)) } }
    }
    if !missing.isEmpty {
      for m in missing { launch(m) }
      return
    }

    // Use logical state, not NSWorkspace.frontmostApplication — the latter may
    // not have committed our previous activate() yet.
    let frontPid = logicalPid
    let ordered = procs.sorted { mruRank($0.pid) < mruRank($1.pid) }
    let frontInApp = frontPid != nil && procs.contains { $0.pid == frontPid }

    if appNames.count == 1 {
      dbg("exec \(appNames[0]) frontPid=\(frontPid ?? -1) frontInApp=\(frontInApp)")
      if frontInApp {
        cycleAppWindows(procs.map { $0.pid })
      } else {
        focusRealWindow(ordered[0].pid)
      }
      return
    }

    if let f = frontPid, let idx = ordered.firstIndex(where: { $0.pid == f }) {
      activate(ordered[(idx + 1) % ordered.count].pid)
    } else {
      activate(ordered[0].pid)
    }
  }

  // Commands are enqueued as-is; when the burst settles drain() simulates every
  // queued command against logical state to compute the final target, then makes
  // one OS call. N rapid keypresses → 1 activate(), with no OS reads mid-burst.

  func enqueue(_ appNames: [String]) {
    if commandQueue.isEmpty {
      // First command in a potential burst: capture the logical state we're coming
      // FROM and execute immediately — zero latency for single keypresses.
      burstStartPid = logicalPid
      burstStartWid = logicalWid
      dbg("burst-first \(appNames) startPid=\(burstStartPid ?? -1)")
      executeCommand(appNames)
    }
    commandQueue.append(appNames)
    drainToken &+= 1
    let token = drainToken
    DispatchQueue.main.asyncAfter(deadline: .now() + DRAIN_IDLE) {
      guard self.drainToken == token else { return }
      self.drain()
    }
  }

  func drain() {
    guard !commandQueue.isEmpty else { return }
    let queue = commandQueue
    let startPid = burstStartPid
    let startWid = burstStartWid
    commandQueue.removeAll()
    burstStartPid = nil
    burstStartWid = nil

    // Single command: already executed on arrival, nothing to correct.
    if queue.count == 1 {
      dbg("drain single noop")
      return
    }
    dbg("drain burst count=\(queue.count) startPid=\(startPid ?? -1)")

    // Resolve all pids once up front.
    var pidCache: [String: [pid_t]] = [:]
    func pids(for name: String) -> [pid_t] {
      if let cached = pidCache[name] { return cached }
      let result = matchingPids(name)
      pidCache[name] = result
      return result
    }

    // Snapshot current-space windows for simulation — one AX pass for all pids.
    let allPids = Set(queue.flatMap { names in names.flatMap { pids(for: $0) } })
    var winMap: [pid_t: [AXWin]] = [:]
    for pid in allPids { winMap[pid] = realWindows([pid]) }

    // Simulate ALL commands from the burst-start state (before the first command
    // fired). This gives the true final intent of the burst independently of what
    // the first command already did.
    var simPid: pid_t? = startPid
    var simWid: CGWindowID? = startWid
    var finalNames: [String] = queue[0]
    var finalMissing: [String] = []
    var finalStepIsAppSwitch = false

    for names in queue {
      let allP = names.flatMap { pids(for: $0) }
      let missing = names.filter { pids(for: $0).isEmpty }
      if !missing.isEmpty {
        finalNames = names
        finalMissing = missing
        simPid = nil
        simWid = nil
        finalStepIsAppSwitch = true
        continue
      }
      finalNames = names
      finalMissing = []

      let frontInApp = simPid != nil && allP.contains(simPid!)

      if names.count == 1 && frontInApp {
        // Window cycle within app — advance through visible (current-space) windows.
        // simWid may be nil after an app-switch step; use lastWid as the effective
        // starting position rather than blindly falling back to wins.first, which
        // would produce the wrong wid and trigger a spurious drain override.
        let wins = allP.flatMap { winMap[$0] ?? [] }.sorted { $0.wid < $1.wid }
        let effectiveWid = simWid ?? (simPid.flatMap { lastWid[$0] })
        if let wid = effectiveWid, let i = wins.firstIndex(where: { $0.wid == wid }) {
          if wins.count > 1 {
            // Multiple on-space windows — advance to next.
            let next = wins[(i + 1) % wins.count]
            simPid = next.pid
            simWid = next.wid
            finalStepIsAppSwitch = false
          } else {
            // Single on-space window: a real cycle would cross spaces. Mark unknown
            // so the override check defers to whatever the first command already did.
            simWid = nil
            finalStepIsAppSwitch = true
          }
        } else if effectiveWid != nil {
          // Starting window is off-space — can't simulate accurately.
          // Preserve so the override check doesn't fire a spurious correction.
          simWid = effectiveWid
          finalStepIsAppSwitch = false
        } else if let first = wins.first(where: { $0.pid == simPid }) {
          // simPid has an on-space window and no prior preference — start there.
          simPid = first.pid
          simWid = first.wid
          finalStepIsAppSwitch = false
        } else {
          // simPid has no on-space windows (e.g. ff2 is off-space while wins only
          // contains ff1). Can't determine which window a real cycle would target.
          // Treat as unknown so the override check defers to the first command.
          simWid = nil
          finalStepIsAppSwitch = true
        }
      } else {
        // App switch: pick the MRU pid of this key's target set.
        let ordered = allP.sorted { mruRank($0) < mruRank($1) }
        simPid = ordered.first
        simWid = nil
        finalStepIsAppSwitch = true
      }
    }

    dbg(
      "drain override? simPid=\(simPid ?? -1) simWid=\(simWid ?? 0) logicalPid=\(logicalPid ?? -1) logicalWid=\(logicalWid ?? 0) appSwitch=\(finalStepIsAppSwitch)"
    )

    // If the first command already landed on the correct final target, nothing to do.
    if simPid == logicalPid && (simWid == nil || simWid == logicalWid) {
      dbg("drain no override needed")
      return
    }

    if !finalMissing.isEmpty {
      for m in finalMissing { launch(m) }
      return
    }

    // App switch: use focusRealWindow to avoid executeCommand reading the now-stale
    // logicalPid and erroneously entering the window-cycle path.
    if finalStepIsAppSwitch, let pid = simPid {
      dbg("drain override app-switch pid=\(pid)")
      focusRealWindow(pid)
      return
    }

    // Window cycle that advanced to a specific on-space window.
    if let pid = simPid, let wid = simWid,
      wid != logicalWid || pid != logicalPid,
      let w = winMap[pid]?.first(where: { $0.wid == wid })
    {
      dbg("drain override direct-raise pid=\(pid) wid=\(wid)")
      focus(w)
      return
    }

    // Fallback: cross-space cycle or single-window wrap — executeCommand +
    // cycleAppWindows detects the cross-space case via offSpace / cycleCrossSpace.
    executeCommand(finalNames)
  }
}
