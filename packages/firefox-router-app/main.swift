import AppKit

// FirefoxRouter.app — the macOS default http/https handler. LaunchServices
// delivers each clicked link here; we pass it to firefox-router, which picks
// the Firefox profile. Launched directly (Spotlight, Finder) it just opens
// Firefox, like running firefox-router with no URL.
let router = "@router@"

func route(_ arguments: [String]) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: router)
  process.arguments = arguments
  try? process.run()
}

final class Delegate: NSObject, NSApplicationDelegate {
  var opened = false

  func application(_ application: NSApplication, open urls: [URL]) {
    opened = true
    for url in urls {
      route([url.absoluteString])
    }
  }

  // The launch's link arrives just after launch finishes, so wait a moment
  // before deciding this was a plain launch. Quitting afterwards keeps nothing
  // resident; the next link relaunches the app.
  func applicationDidFinishLaunching(_ notification: Notification) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      if !self.opened {
        route([])
      }
      NSApp.terminate(nil)
    }
  }
}

let delegate = Delegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
