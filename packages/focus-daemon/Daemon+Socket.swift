import AppKit
import Foundation

extension Daemon {
  func handle(_ msg: String) {
    let key = msg.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty { return }
    if key == "--recheck-bar" {
      reconcileFirefox()
      scheduleRefresh()
      return
    }
    if key.hasPrefix("--probe ") {
      probe(String(key.dropFirst("--probe ".count)))
      return
    }
    let appNames = key.split(separator: " ").map(String.init)
    dbg("recv \(key)")
    enqueue(appNames)
  }

  func probe(_ appName: String) {
    let front = NSWorkspace.shared.frontmostApplication
    fputs("focusd probe: \(appName) matchingPids=\(matchingPids(appName))\n", stderr)
    fputs(
      "  frontmost: pid=\(front?.processIdentifier ?? -1) bundle=\(front?.bundleIdentifier ?? "nil")\n",
      stderr)
    fputs("  logical: pid=\(logicalPid ?? -1) wid=\(logicalWid ?? 0)\n", stderr)
    fputs("  all org.mozilla.firefox processes:\n", stderr)
    for a in NSWorkspace.shared.runningApplications
    where a.bundleIdentifier == "org.mozilla.firefox" {
      let p = a.processIdentifier
      fputs(
        "   pid=\(p) policy=\(a.activationPolicy.rawValue) name=\(a.localizedName ?? "") exe=\(a.executableURL?.lastPathComponent ?? "")\n",
        stderr)
      let axApp = AXUIElementCreateApplication(p)
      var wv: CFTypeRef?
      AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wv)
      for w in (wv as? [AXUIElement]) ?? [] {
        let wid = axWindowID(w).map(String.init) ?? "nil"
        let t = axString(w, kAXTitleAttribute as String) ?? ""
        fputs("      [win] wid=\(wid) title=\(t)\n", stderr)
      }
      if let f = axElement(axApp, kAXFocusedWindowAttribute as String) {
        fputs("      [focused] wid=\(axWindowID(f).map(String.init) ?? "nil")\n", stderr)
      }
    }
  }

  func startSocketServer() {
    unlink(SOCK_PATH)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      fputs("socket() failed\n", stderr)
      exit(1)
    }
    var addr = makeSockaddr(SOCK_PATH)
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
    }
    guard bound == 0 else {
      fputs("bind() failed\n", stderr)
      exit(1)
    }
    guard listen(fd, 64) == 0 else {
      fputs("listen() failed\n", stderr)
      exit(1)
    }

    DispatchQueue.global(qos: .userInteractive).async {
      while true {
        let client = accept(fd, nil, nil)
        if client < 0 { continue }
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(client, &buf, buf.count)
        close(client)
        if n > 0 {
          let msg = String(decoding: buf[0..<n], as: UTF8.self)
          DispatchQueue.main.async { self.handle(msg) }
        }
      }
    }
  }

  func start() {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
    let nc = NSWorkspace.shared.notificationCenter
    nc.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        self?.onFront(app.processIdentifier)
      }
    }
    nc.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.onSpaceChanged()
    }
    if let f = NSWorkspace.shared.frontmostApplication { onFront(f.processIdentifier) }
    scheduleRefresh()
    startSocketServer()
  }
}
