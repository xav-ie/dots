import AppKit

// confirm-open <app name> — NSAlert with the app's real icon.
// Exit 0 = Open (default button / Return), exit 1 = Cancel (Escape).
let name = CommandLine.arguments.dropFirst().first ?? "this app"

// Single instance: a second launch just pokes the one already prompting
// (SIGUSR1 -> re-activate) instead of stacking another alert.
let pidFile = "/tmp/confirm-open.pid"
if let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
  let other = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
  kill(other, 0) == 0
{
  kill(other, SIGUSR1)
  exit(1)
}
try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)

signal(SIGUSR1, SIG_IGN)
let sigsrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
sigsrc.setEventHandler { NSApp.activate(ignoringOtherApps: true) }
sigsrc.resume()

let alert = NSAlert()
alert.messageText = "Open \(name)?"
alert.informativeText = "It takes a while to start."
// fullPath(forApplication:) is the only name→bundle lookup that doesn't need a
// bundle id; falls back to the obvious path if LaunchServices doesn't know it.
if let path = NSWorkspace.shared.fullPath(forApplication: name)
  ?? ["/Applications/\(name).app"].first(where: { FileManager.default.fileExists(atPath: $0) })
{
  alert.icon = NSWorkspace.shared.icon(forFile: path)
}
alert.addButton(withTitle: "Open")  // first button = default = Return
alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"  // Escape
alert.window.level = .floating

exit(alert.runModal() == .alertFirstButtonReturn ? 0 : 1)
