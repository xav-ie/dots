// DockOverlay — capture-safe stand-ins for Dock's hover UI.
//
// Dock draws Mission Control's hover outline + window title and the Dock icon
// name tooltips in its own windows, which ignore sharingType: they always reach
// a screen share. The hide-windows dylib (running inside Dock) therefore never
// lets Dock draw them; instead it reports what Dock wanted to show, and we draw
// the same thing here in sharingType = .none panels — on screen for you, absent
// from every capture.
//
// Protocol: distributed notification com.x.hidewin.dock-ui, object =
//   "outline\t<x>\t<y>\t<w>\t<h>\t<title>"   hovered window in Mission Control
//   "label\t<x>\t<y>\t<w>\t<h>\t<text>"      Dock icon name tooltip
//   "outline\thide" / "label\thide"
// Rects are global CoreGraphics points (top-left origin). The title is drawn
// centred on the outline, where Dock puts it.

import AppKit

let DOCK_UI = Notification.Name("com.x.hidewin.dock-ui")

// The hover outline is a purple neon tube centred on the window's edge (so
// the window's rounded corners can't peek past it): a violet tube with a
// purple glow, a lavender core and a white-hot centre line.
private let OUTLINE_RADIUS: CGFloat = 7
private let OUTLINE_GLOW: CGFloat = 16
private let OUTLINE_MARGIN: CGFloat = OUTLINE_GLOW * 2  // room for the glow
private let OUTLINE_STROKES: [(width: CGFloat, color: NSColor, glow: Bool)] = [
  (6, NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 1), true),  // violet tube
  (3, NSColor(srgbRed: 0.85, green: 0.70, blue: 1.0, alpha: 1), false),  // lavender core
  (1.2, NSColor(white: 1, alpha: 0.9), false),  // white-hot centre
]
private let OUTLINE_GLOW_COLOR = NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1)
private let PILL_HEIGHT: CGFloat = 26
private let PILL_PAD: CGFloat = 12
// Dock's label rect includes room for its shadow and tail; centring our
// tail-less pill in it floats it too far above the icon.
private let LABEL_DROP: CGFloat = 6

private func overlayPanel() -> NSPanel {
  let p = NSPanel(
    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
    defer: true)
  p.sharingType = .none
  p.level = .popUpMenu  // above Mission Control's layers (18/20)
  p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
  p.ignoresMouseEvents = true
  p.backgroundColor = .clear
  p.isOpaque = false
  p.hasShadow = false
  p.hidesOnDeactivate = false
  return p
}

// CoreGraphics global (top-left origin) → Cocoa screen (bottom-left origin).
private func cocoaRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
  let primary = NSScreen.screens.first?.frame.height ?? 0
  return NSRect(x: x, y: primary - y - h, width: w, height: h)
}

// A capsule with one line of text. Opaque-ish with a hairline rim and the
// window's drop shadow, so it stays legible over any window it lands on.
private final class Pill {
  let panel = overlayPanel()
  private let text = NSTextField(labelWithString: "")
  private let capsule = NSView()

  init(fill: NSColor, ink: NSColor, rim: NSColor, weight: NSFont.Weight) {
    text.font = NSFont.systemFont(ofSize: 13, weight: weight)
    text.textColor = ink
    text.alignment = .center
    text.lineBreakMode = .byTruncatingMiddle
    capsule.wantsLayer = true
    capsule.layer?.backgroundColor = fill.cgColor
    capsule.layer?.cornerRadius = PILL_HEIGHT / 2
    capsule.layer?.cornerCurve = .continuous
    capsule.layer?.borderColor = rim.cgColor
    capsule.layer?.borderWidth = 1
    capsule.addSubview(text)
    panel.contentView = capsule
    panel.hasShadow = true
  }

  // Centre a pill for `string` on `center` (Cocoa coordinates).
  func show(_ string: String, center: NSPoint, maxWidth: CGFloat) {
    text.stringValue = string
    text.sizeToFit()  // exact width the text needs, insets included
    let fit = text.frame.size
    let w = min(ceil(fit.width) + PILL_PAD * 2, maxWidth)
    panel.setFrame(
      NSRect(x: center.x - w / 2, y: center.y - PILL_HEIGHT / 2, width: w, height: PILL_HEIGHT),
      display: false)
    capsule.frame = NSRect(x: 0, y: 0, width: w, height: PILL_HEIGHT)
    text.frame = NSRect(
      x: PILL_PAD, y: (PILL_HEIGHT - fit.height) / 2, width: w - PILL_PAD * 2, height: fit.height)
    panel.orderFrontRegardless()
    panel.invalidateShadow()
  }

  func hide() { panel.orderOut(nil) }
}

final class DockOverlay {
  private let outline = overlayPanel()
  private var strokes: [CAShapeLayer] = []
  private let title = Pill(
    fill: NSColor(white: 0.97, alpha: 0.97), ink: .black, rim: NSColor(white: 0, alpha: 0.18),
    weight: .semibold)
  private let label = Pill(
    fill: NSColor(white: 0.18, alpha: 0.9), ink: .white, rim: NSColor(white: 1, alpha: 0.28),
    weight: .medium)

  init() {
    let ring = NSView()
    ring.wantsLayer = true
    for s in OUTLINE_STROKES {
      let l = CAShapeLayer()
      l.fillColor = nil
      l.lineWidth = s.width
      l.strokeColor = s.color.cgColor
      l.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
      if s.glow {
        l.shadowColor = OUTLINE_GLOW_COLOR.cgColor
        l.shadowOpacity = 1
        l.shadowRadius = OUTLINE_GLOW
        l.shadowOffset = .zero
      }
      ring.layer?.addSublayer(l)
      strokes.append(l)
    }
    outline.contentView = ring

    DistributedNotificationCenter.default().addObserver(
      forName: DOCK_UI, object: nil, queue: .main
    ) { [weak self] note in
      guard let msg = note.object as? String else { return }
      self?.handle(msg.components(separatedBy: "\t"))
    }
  }

  private func handle(_ f: [String]) {
    guard let kind = f.first else { return }
    let rect: NSRect? =
      f.count >= 6
      ? zip4(f[1], f[2], f[3], f[4]).map { cocoaRect($0, $1, $2, $3) } : nil
    if let r = rect, r.width <= 0 || r.height <= 0 { return }  // not laid out yet
    let text = f.count >= 6 ? f[5...].joined(separator: "\t") : ""
    switch (kind, rect) {
    case ("outline", let r?):
      outline.setFrame(r.insetBy(dx: -OUTLINE_MARGIN, dy: -OUTLINE_MARGIN), display: false)
      let edge = CGPath(
        roundedRect: CGRect(x: OUTLINE_MARGIN, y: OUTLINE_MARGIN, width: r.width, height: r.height),
        cornerWidth: OUTLINE_RADIUS, cornerHeight: OUTLINE_RADIUS, transform: nil)
      for l in strokes { l.path = edge }
      outline.orderFrontRegardless()
      if text.isEmpty {
        title.hide()
      } else {
        title.show(text, center: NSPoint(x: r.midX, y: r.midY), maxWidth: r.width)
      }
    case ("outline", nil):
      outline.orderOut(nil)
      title.hide()
    case ("label", let r?):
      label.show(text, center: NSPoint(x: r.midX, y: r.midY - LABEL_DROP), maxWidth: 600)
    case ("label", nil):
      label.hide()
    default:
      break
    }
  }
}

private func zip4(_ a: String, _ b: String, _ c: String, _ d: String)
  -> (CGFloat, CGFloat, CGFloat, CGFloat)?
{
  guard let x = Double(a), let y = Double(b), let w = Double(c), let h = Double(d) else {
    return nil
  }
  return (CGFloat(x), CGFloat(y), CGFloat(w), CGFloat(h))
}
