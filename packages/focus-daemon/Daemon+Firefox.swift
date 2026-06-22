import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension Daemon {
  // Non-native fullscreen Firefox sits at (0,0) over the notch and macOS won't
  // auto-hide the menu bar for it, so it chins itself and every other app. Hold
  // it at y=BAR_HEIGHT; the off-screen bottom strip is absorbed by the
  // userChrome.css DOM-fullscreen inset (see modules/_lib/firefox). Matched via AX
  // (AXUnknown subrole + full AX size), not CGWindowList — a moved Firefox's
  // rendered bounds shrink while AX still reports full size. Only kAXPosition is
  // settable (kAXSize errors -25200; AX also clamps y >= 0).

  func fullscreenFirefoxWindows() -> [(win: AXUIElement, y: Int)] {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    let W = bounds.width
    let H = bounds.height
    var out: [(AXUIElement, Int)] = []
    for app in NSWorkspace.shared.runningApplications
    where app.bundleIdentifier == "org.mozilla.firefox" {
      let axApp = AXUIElementCreateApplication(app.processIdentifier)
      var wv: CFTypeRef?
      guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wv) == .success,
        let wins = wv as? [AXUIElement]
      else { continue }
      for w in wins {
        guard axString(w, kAXSubroleAttribute as String) == (kAXUnknownSubrole as String)
        else { continue }
        guard let size = axCGSize(w, kAXSizeAttribute as String),
          size.width >= W - 2 && size.height >= H - 12
        else { continue }
        let pos = axCGPoint(w, kAXPositionAttribute as String) ?? .zero
        out.append((w, Int(pos.y)))
      }
    }
    return out
  }

  func setWindowOriginY(_ win: AXUIElement, _ y: Int) {
    var p = CGPoint(x: 0, y: CGFloat(y))
    if let v = AXValueCreate(.cgPoint, &p) {
      AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
    }
  }

  func reconcileFirefox() {
    DispatchQueue.global(qos: .userInitiated).async {
      for w in self.fullscreenFirefoxWindows() {
        if w.y != BAR_HEIGHT { self.setWindowOriginY(w.win, BAR_HEIGHT) }
      }
    }
  }

  func onFront(_ pid: pid_t) {
    recordFront(pid)
    acceptOSFront(pid)
    reconcileFirefox()
  }
}
