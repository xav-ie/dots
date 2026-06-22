import Foundation

let SOCK_PATH = "/tmp/focusd.sock"
// Only used to cross Spaces: AX is Space-scoped and can neither see nor focus a
// window on another desktop, so the rare cross-Space jump shells out to yabai
// (`space --focus`). The hot path never touches it.
let YABAI = ProcessInfo.processInfo.environment["FOCUSD_YABAI"] ?? "yabai"
// How far below the notch to hold the fullscreen Firefox window (= sketchybar height).
let BAR_HEIGHT = Int(ProcessInfo.processInfo.environment["FOCUSD_BAR_HEIGHT"] ?? "32") ?? 32

let DEBUG = ProcessInfo.processInfo.environment["FOCUSD_DEBUG"] != nil
func dbg(_ s: @autoclosure () -> String) {
  guard DEBUG else { return }
  fputs("[\(String(format: "%.3f", Date().timeIntervalSince1970))] \(s())\n", stderr)
}

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
