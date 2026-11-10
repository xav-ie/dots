import AppKit

// yubikey-touch-prompt: a "Touch your YubiKey" panel shown while the YubiKey
// waits for a touch, much like the system's Touch ID prompt.
//
// While an OpenPGP operation waits on the key's touch policy, the CCID driver
// logs "Time extension received" several times a second, and stops once the
// key is touched or gives up. So the panel shows on the first of those messages
// and hides when they have been quiet for `quiet` seconds.
let quiet: TimeInterval = 1.0
let predicate =
  #"subsystem == "com.apple.CryptoTokenKit" AND category == "ccid" AND eventMessage == "Time extension received""#

final class Prompt {
  let panel: NSPanel
  var hide: DispatchWorkItem?

  init() {
    let size = NSSize(width: 300, height: 76)
    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    // Above other windows on every Space, without taking focus from the PIN
    // dialog or the terminal.
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.alphaValue = 0

    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    // A mask rather than a layer corner radius: the window shadow follows the
    // mask, so no square corners show behind the rounded panel.
    background.maskImage = NSImage(size: size, flipped: false) { rect in
      NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
      return true
    }

    let icon = NSImageView(frame: NSRect(x: 18, y: 18, width: 40, height: 40))
    icon.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "YubiKey")?
      .withSymbolConfiguration(.init(pointSize: 28, weight: .regular))
    icon.contentTintColor = .controlAccentColor

    let title = NSTextField(labelWithString: "Touch your YubiKey")
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.frame = NSRect(x: 70, y: 38, width: 220, height: 20)

    let detail = NSTextField(labelWithString: "It's blinking and waiting for a tap")
    detail.font = .systemFont(ofSize: 12)
    detail.textColor = .secondaryLabelColor
    detail.frame = NSRect(x: 70, y: 18, width: 220, height: 16)

    for view in [icon, title, detail] { background.addSubview(view) }
    panel.contentView = background
  }

  func poke() {
    if panel.alphaValue == 0 {
      // Top centre of the screen the pointer is on, where Touch ID's prompt sits.
      let mouse = NSEvent.mouseLocation
      let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
      if let visible = screen?.visibleFrame {
        panel.setFrameOrigin(
          NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 24
          ))
      }
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
    }
    hide?.cancel()
    let work = DispatchWorkItem { [panel] in
      NSAnimationContext.runAnimationGroup(
        { $0.duration = 0.2; panel.animator().alphaValue = 0 },
        completionHandler: { panel.orderOut(nil) })
    }
    hide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + quiet, execute: work)
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let prompt = Prompt()

let stream = Process()
stream.executableURL = URL(fileURLWithPath: "/usr/bin/log")
stream.arguments = ["stream", "--level", "debug", "--style", "compact", "--predicate", predicate]
let pipe = Pipe()
stream.standardOutput = pipe
pipe.fileHandleForReading.readabilityHandler = { handle in
  let chunk = handle.availableData
  if String(decoding: chunk, as: UTF8.self).contains("Time extension received") {
    DispatchQueue.main.async { prompt.poke() }
  }
}
// launchd restarts the agent, and with it the stream, if `log` ever exits.
stream.terminationHandler = { _ in exit(1) }
try stream.run()

app.run()
