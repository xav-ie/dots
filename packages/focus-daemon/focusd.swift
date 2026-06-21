// focusd — a resident daemon that focuses/cycles apps for lcmd+<n> hotkeys.
//
// Why a daemon: skhd spawns the hotkey command on every key event, and with a
// 15ms key-repeat a held key fires dozens of times a second. A one-shot process
// can't keep up — it takes ~50ms just to start, so repeats pile into a backlog.
// This daemon stays resident: a tiny client (this same binary, invoked with app
// names) sends one line over a unix socket and exits in ~1ms, and the daemon
// coalesces the burst so a held key settles on a switch or two instead of dozens.
//
// Focus order ("which app/window is current, and what was recent") comes from
// AppKit directly — NSWorkspace activation notifications and frontmostApplication
// — so it is always accurate, including across cmd+tab, mouse clicks, and the
// fullscreen Firefox window that yabai can't see. Activation uses
// NSRunningApplication.activate (sub-millisecond, in-process). Only per-window
// cycling within a single app shells out to yabai.
//
// Usage:
//   focusd --daemon         run the resident daemon (launchd)
//   focusd Firefox          client: ask the daemon to focus/cycle Firefox
//   focusd Messages Signal  client: cycle across several apps

import AppKit
import Foundation

let SOCK_PATH = "/tmp/focusd.sock"
let YABAI = ProcessInfo.processInfo.environment["FOCUSD_YABAI"] ?? "yabai"

// MARK: - small helpers

@discardableResult
func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: Data) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: launchPath)
  p.arguments = args
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = FileHandle.nullDevice
  do { try p.run() } catch { return (-1, Data()) }
  let out = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return (p.terminationStatus, out)
}

func resolve(_ tool: String) -> String {
  if tool.hasPrefix("/") { return tool }
  for dir in [
    "/run/current-system/sw/bin", "/etc/profiles/per-user/\(NSUserName())/bin", "/usr/local/bin",
    "/opt/homebrew/bin", "/usr/bin",
  ] {
    let path = "\(dir)/\(tool)"
    if FileManager.default.isExecutableFile(atPath: path) { return path }
  }
  return tool
}

func makeSockaddr(_ path: String) -> sockaddr_un {
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  let cap = MemoryLayout.size(ofValue: addr.sun_path)
  path.withCString { cs in
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cs, cap - 1)
    }
  }
  return addr
}

// MARK: - yabai window model (only used for per-window cycling)

struct YWindow: Decodable {
  let id: Int
  let app: String
  let title: String
  let hasFocus: Bool
  enum CodingKeys: String, CodingKey {
    case id, app, title
    case hasFocus = "has-focus"
  }
}

func yabaiWindows() -> [YWindow] {
  let (status, out) = run(resolve(YABAI), ["-m", "query", "--windows"])
  guard status == 0 else { return [] }
  return (try? JSONDecoder().decode([YWindow].self, from: out)) ?? []
}

// MARK: - daemon

final class Daemon {
  // Most-recently-activated pids, newest first. Maintained from NSWorkspace.
  var mru: [pid_t] = []
  // Leading-edge coalescing: when the same message was just handled, drop it.
  var lastHandled: [String: Date] = [:]
  let coalesceWindow: TimeInterval = 0.06

  func recordFront(_ pid: pid_t) {
    mru.removeAll { $0 == pid }
    mru.insert(pid, at: 0)
    if mru.count > 64 { mru.removeLast() }
  }

  func mruRank(_ pid: pid_t) -> Int {
    mru.firstIndex(of: pid) ?? Int.max
  }

  // Running, regular (dock-visible) apps whose executable name matches `name`
  // case-insensitively — mirrors `pgrep -ix`, so "Firefox" matches both
  // lowercase "firefox" profile processes while excluding helpers.
  func matchingPids(_ name: String) -> [pid_t] {
    let want = name.lowercased()
    return NSWorkspace.shared.runningApplications.filter { app in
      guard app.activationPolicy == .regular else { return false }
      let exe = app.executableURL?.lastPathComponent.lowercased()
      let loc = app.localizedName?.lowercased()
      return exe == want || loc == want
    }.map { $0.processIdentifier }
  }

  func activate(_ pid: pid_t) {
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
  }

  func launch(_ name: String) {
    run(resolve("open"), ["-a", name])
  }

  // Cycle the windows of `app` round-robin via yabai. Returns false if the app
  // has no yabai-visible window (e.g. a lone fullscreen Firefox), so the caller
  // can fall back to plain activation.
  func cycleWindows(_ app: String) -> Bool {
    let want = app.lowercased()
    let wins = yabaiWindows().filter {
      $0.app.lowercased() == want && $0.title != "Picture-in-Picture"
    }
    if wins.isEmpty { return false }
    let target: YWindow
    if let i = wins.firstIndex(where: { $0.hasFocus }) {
      target = wins[(i + 1) % wins.count]
    } else {
      target = wins[0]
    }
    run(resolve(YABAI), ["-m", "window", "--focus", String(target.id)])
    return true
  }

  func execute(_ appNames: [String]) {
    var procs: [(app: String, pid: pid_t)] = []
    var missing: [String] = []
    for name in appNames {
      let pids = matchingPids(name)
      if pids.isEmpty { missing.append(name) } else { for p in pids { procs.append((name, p)) } }
    }
    if !missing.isEmpty {
      for m in missing { launch(m) }
      return
    }

    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier

    if procs.count == 1 {
      let one = procs[0]
      // Already in this app -> cycle its windows; otherwise activate it, which
      // brings the OS's most-recently-used window (and works for a fullscreen
      // window yabai can't see).
      if front == one.pid {
        if !cycleWindows(one.app) { activate(one.pid) }
      } else {
        activate(one.pid)
      }
      return
    }

    // Several processes — multiple apps (Messages + Signal) or Firefox profiles.
    let ordered = procs.sorted { mruRank($0.pid) < mruRank($1.pid) }
    if let f = front, let idx = ordered.firstIndex(where: { $0.pid == f }) {
      activate(ordered[(idx + 1) % ordered.count].pid)  // inside -> next
    } else {
      activate(ordered[0].pid)  // outside -> most-recently-used
    }
  }

  func handle(_ msg: String) {
    let key = msg.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty { return }
    let now = Date()
    if let t = lastHandled[key], now.timeIntervalSince(t) < coalesceWindow {
      lastHandled[key] = now  // slide the window so the whole burst is dropped
      return
    }
    lastHandled[key] = now
    execute(key.split(separator: " ").map(String.init))
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
    let nc = NSWorkspace.shared.notificationCenter
    nc.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        self?.recordFront(app.processIdentifier)
      }
    }
    if let f = NSWorkspace.shared.frontmostApplication { recordFront(f.processIdentifier) }
    startSocketServer()
  }
}

// MARK: - client

func sendToDaemon(_ args: [String]) {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { exit(1) }
  defer { close(fd) }
  var addr = makeSockaddr(SOCK_PATH)
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
  }
  guard ok == 0 else { exit(1) }  // daemon not up; nothing to do
  let msg = args.joined(separator: " ")
  _ = msg.withCString { write(fd, $0, strlen($0)) }
}

// MARK: - entry

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--daemon" {
  let daemon = Daemon()
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)  // background, no dock icon / menu bar
  daemon.start()
  app.run()
} else if !args.isEmpty {
  sendToDaemon(args)
} else {
  fputs("usage: focusd --daemon | focusd <AppName>...\n", stderr)
  exit(2)
}

