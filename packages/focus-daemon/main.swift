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
// a local logical state updated synchronously before every OS call — we never
// query NSWorkspace.frontmostApplication to decide what to focus next, because
// that reflects what the WindowServer has committed, not what we last commanded.
//
// "Fire first, correct later": the first command in a burst executes immediately
// (zero latency for single taps). Subsequent commands within DRAIN_IDLE are
// queued; when the burst settles, drain() simulates the full burst from the
// burst-start logical state and fires an override only if the final target differs
// from where the first command landed. Single taps cost 0ms; rapid bursts get
// corrected to the right final state.
//
// Files:
//   Helpers.swift        globals, run/resolve/makeSockaddr/dbg
//   Windows.swift        AX types + helpers, YWindow, fetchYabaiWindows
//   Daemon.swift         class definition, state, MRU, logical state
//   Daemon+Firefox.swift notch management
//   Daemon+Focus.swift   focus primitives, window enumeration, cycling
//   Daemon+Queue.swift   executeCommand, enqueue, drain
//   Daemon+Socket.swift  handle, probe, socket server, start
//
// Usage:
//   focusd --daemon         run the resident daemon (launchd)
//   focusd Firefox          client: ask the daemon to focus/cycle Firefox
//   focusd Messages Signal  client: cycle across several apps

import AppKit
import Foundation

func sendToDaemon(_ args: [String]) {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { exit(1) }
  defer { close(fd) }
  var addr = makeSockaddr(SOCK_PATH)
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
  }
  guard ok == 0 else { exit(1) }
  let msg = args.joined(separator: " ")
  _ = msg.withCString { write(fd, $0, strlen($0)) }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--daemon" {
  let daemon = Daemon()
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  daemon.start()
  app.run()
} else if !args.isEmpty {
  sendToDaemon(args)
} else {
  fputs("usage: focusd --daemon | focusd <AppName>...\n", stderr)
  exit(2)
}
