// hidewin-bar — menubar manager for capture-hidden apps.
//
// Windows are VISIBLE by default (so recorders like Dayflow keep working).
// This menubar app's "Screenshare Mode" hides everything from capture for
// a meeting; you then reveal the specific apps you want to present.
//
// The dropdown is a custom NSPanel with sharingType = .none, NOT an
// NSMenu: native menu windows are a privileged server-rendered surface
// that ignores the sharing flag (verified — the flag sticks but the menu
// is still captured), so a viewer would see you managing the hide list.
// A borderless panel is a normal window and honors .none, so the app list
// itself stays invisible to capture.
//
// The trigger and icon live in sketchybar: the `hidewin` item's plugin
// (plugins/hidewin.nu) OWNS the bar icon and renders/sets it on events. We
// don't touch sketchybar — we only PUBLISH state: on a Screenshare Mode change
// we write ~/.cache/hidewin/mode and post `mode-changed` (a sketchybar event
// the item subscribes to). The plugin's mouse.clicked runs `hidewin panel <x>`,
// posting TOGGLE with the item's x so we place the panel under it.
//
// Targeting is per-PROCESS (pid): two Firefox profile instances share a
// bundle id but are separate processes, so keying by pid lets you reveal
// just the "Work" one.
//
// INJECTION STATE: an app is only controllable if our dylib actually got
// injected into it — which fails for apps that launched at login before
// the session's DYLD_INSERT_LIBRARIES was set (some startup apps). We
// detect this honestly: injected agents announce themselves (the `iam`
// notification); an app that never announces has no agent, so it can't be
// hidden and shows a ⚠ "restart to enable" row instead of a checkbox that
// would silently do nothing. State is per-session (revealed pids in
// memory) — a relaunched app is hidden by default anyway (the fail-safe).

import AppKit

let SHOW = Notification.Name("com.x.hidewin.show")
let HIDE = Notification.Name("com.x.hidewin.hide")
let WHO = Notification.Name("com.x.hidewin.who")
let IAM = Notification.Name("com.x.hidewin.iam")
let TOGGLE = Notification.Name("com.x.hidewin.toggle-panel")
let MODE_CHANGED = Notification.Name("com.x.hidewin.mode-changed")

func post(_ name: Notification.Name, _ object: String?) {
  DistributedNotificationCenter.default().postNotificationName(
    name, object: object, userInfo: nil, deliverImmediately: true)
}

let PANEL_W: CGFloat = 280
let PANEL_RADIUS: CGFloat = 16
let PANEL_PAD: CGFloat = 6
let ROW_W = PANEL_W - PANEL_PAD * 2
let ROW_H: CGFloat = 24
let SEP_H: CGFloat = 9

// Outside of drawing, .cgColor resolves against NSAppearance.current, which here
// is the light default no matter what the panel is actually showing — so resolve
// the appearance explicitly instead of leaning on dynamic colors.
func isDark(_ appearance: NSAppearance) -> Bool {
  appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

func checkImage(_ on: Bool) -> NSImage? {
  on ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
}

func separatorBox() -> NSBox {
  let v = NSBox(frame: NSRect(x: 0, y: 0, width: ROW_W, height: 1))
  v.boxType = .separator
  return v
}

// Top-down layout so the app list reads like a menu, plus the scrim behind the
// rows: .clear glass alone leaves label text unreadable over a bright app behind
// the panel. tintColor can't fix it (it lightens, never darkens), so this puts a
// translucent wash between the glass and the rows — dark and see-through like a
// notification banner, glass edge and refraction intact. It follows the system
// appearance so it stays behind whatever labelColor resolves to.
final class PanelBackground: NSView {
  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = PANEL_RADIUS
    layer?.masksToBounds = true
    applyScrim()
  }
  required init?(coder: NSCoder) { fatalError() }

  // A CGColor is a snapshot, so unlike the labels it won't restyle itself when
  // the system flips between Light and Dark. Re-resolve it when told to — and
  // re-soften the glass, which rebuilds its material (and with it the stock
  // blur radius) on the same flip.
  override func viewDidChangeEffectiveAppearance() {
    applyScrim()
    // The glass IS the window's contentView; its backdrop layer is a sibling of
    // ours, not an ancestor, so patch from the top of the tree.
    guard let glass = window?.contentView else { return }
    DispatchQueue.main.async { Controller.reduceGlassBlur(glass) }
  }

  private func applyScrim() {
    let scrim: NSColor = isDark(effectiveAppearance) ? .black : .white
    layer?.backgroundColor = scrim.withAlphaComponent(0.4).cgColor
  }
}

// A menu-like row: hover-highlights, whole row is clickable. Left slot shows a
// checkmark (revealed), a ⚠ (agent not injected), or nothing (actions/header).
final class HoverRow: NSView {
  enum Mark {
    case check(Bool)
    case warning, none
  }

  var onClick: (() -> Void)?
  private let label = NSTextField(labelWithString: "")
  private let mark = NSImageView()
  private var track: NSTrackingArea?
  private var hovered = false

  init(
    _ title: String, icon: NSImage? = nil, subtitle: String? = nil, mark m: Mark = .none,
    enabled: Bool = true
  ) {
    super.init(frame: NSRect(x: 0, y: 0, width: ROW_W, height: ROW_H))
    wantsLayer = true
    layer?.cornerRadius = PANEL_RADIUS - PANEL_PAD  // concentric with the panel's corners

    var x: CGFloat = 8
    mark.frame = NSRect(x: x, y: (ROW_H - 13) / 2, width: 13, height: 13)
    mark.contentTintColor = .labelColor
    switch m {
    case .check(let on):
      mark.image = checkImage(on)
    case .warning:
      mark.contentTintColor = .systemOrange
      mark.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
    case .none:
      break
    }
    addSubview(mark)
    x += 20

    if let icon {
      icon.size = NSSize(width: 16, height: 16)
      let iv = NSImageView(frame: NSRect(x: x, y: (ROW_H - 16) / 2, width: 16, height: 16))
      iv.image = icon
      addSubview(iv)
      x += 22
    }

    let attr = NSMutableAttributedString(
      string: title, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    if let sub = subtitle {
      attr.append(
        NSAttributedString(
          string: "  — \(sub)",
          attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange,
          ]))
    }
    label.attributedStringValue = attr
    label.textColor = enabled ? .labelColor : .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.frame = NSRect(x: x, y: (ROW_H - 16) / 2, width: ROW_W - x - 8, height: 16)
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }

  func setChecked(_ on: Bool) { mark.image = checkImage(on) }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let t = track { removeTrackingArea(t) }
    let t = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
    addTrackingArea(t)
    track = t
  }
  override func mouseEntered(with event: NSEvent) {
    hovered = true
    applyHighlight()
  }
  override func mouseExited(with event: NSEvent) {
    hovered = false
    applyHighlight()
  }
  // Same CGColor-snapshot problem as the scrim: repaint on an appearance flip.
  override func viewDidChangeEffectiveAppearance() { applyHighlight() }

  // Liquid Glass highlights are colorless — a faint wash, not an accent-filled
  // slab, so the glass underneath still reads through. Light in Dark Mode, dark
  // in Light Mode.
  private func applyHighlight() {
    guard hovered else {
      layer?.backgroundColor = NSColor.clear.cgColor
      return
    }
    let c: NSColor = isDark(effectiveAppearance) ? .white : .black
    layer?.backgroundColor = c.withAlphaComponent(0.15).cgColor
  }
  override func mouseDown(with event: NSEvent) {}  // claim the event so mouseUp fires
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}

final class Controller: NSObject {
  let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: PANEL_W, height: 40),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  var revealed = Set<pid_t>()
  var labels = [pid_t: String]()  // pid -> label; PRESENCE means the agent is injected
  var clickMonitor: Any?
  var lastMonitorClose: Date?  // when a click-outside last closed the panel
  // Screenshare Mode: OFF (default) = everything visible so recorders like
  // Dayflow work; ON = hide all from capture (for a meeting), reveal to present.
  var screenshareMode = false
  var launchObserver: Any?

  override init() {
    super.init()
    panel.sharingType = .none  // the app-list window is never captured
    panel.level = .popUpMenu
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false

    DistributedNotificationCenter.default().addObserver(
      forName: TOGGLE, object: nil, queue: .main
    ) { [weak self] note in
      let x = (note.object as? String).flatMap(Double.init).map { CGFloat($0) }
      self?.togglePanel(anchorX: x)
    }

    DistributedNotificationCenter.default().addObserver(
      forName: IAM, object: nil, queue: .main
    ) { [weak self] note in
      guard let self, let s = note.object as? String else { return }
      let parts = s.components(separatedBy: "\t")
      guard parts.count == 2, let pid = pid_t(parts[0]) else { return }
      // Refresh when a pid first proves it's injected (⚠ → checkbox) OR when its
      // label improves (e.g. Firefox's "— Work" suffix set once a window is key).
      let changed = labels[pid] != parts[1]
      labels[pid] = parts[1]
      if changed && panel.isVisible { buildContent() }
    }
    post(WHO, nil)
    // Fail safe: if we were hiding when last quit (e.g. crashed mid-meeting),
    // restore that state rather than silently un-hiding.
    if UserDefaults.standard.bool(forKey: "screenshareMode") {
      setScreenshareMode(true)
    } else {
      publishMode()
    }
  }

  // ON hides everything (except already-revealed apps) and keeps new apps hidden
  // as they launch; OFF makes everything visible again.
  func setScreenshareMode(_ on: Bool) {
    screenshareMode = on
    UserDefaults.standard.set(on, forKey: "screenshareMode")
    publishMode()
    if on {
      post(HIDE, nil)
      for pid in revealed { post(SHOW, String(pid)) }
      if launchObserver == nil {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
          forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
          guard let self, screenshareMode,
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
          else { return }
          if !revealed.contains(app.processIdentifier) {
            post(HIDE, String(app.processIdentifier))
          }
        }
      }
    } else {
      post(SHOW, nil)
      if let o = launchObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(o)
        launchObserver = nil
      }
    }
  }

  // Publish Screenshare Mode state for the sketchybar plugin, which OWNS the
  // bar icon. The plugin reads ~/.cache/hidewin/mode on the `mode-changed`
  // event (bound to the notification posted here) and on its own render.
  func publishMode() {
    let dir = ("~/.cache/hidewin" as NSString).expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? (screenshareMode ? "on" : "off").write(
      toFile: "\(dir)/mode", atomically: true, encoding: .utf8)
    post(MODE_CHANGED, nil)
  }

  func runningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
      .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
  }

  func togglePanel(anchorX: CGFloat?) {
    if panel.isVisible {
      closePanel()
      return
    }
    // Clicking the sketchybar item to DISMISS also trips our global click
    // monitor, which closes the panel a beat before this toggle arrives. Don't
    // immediately reopen in that case.
    if let t = lastMonitorClose, Date().timeIntervalSince(t) < 0.3 {
      lastMonitorClose = nil
      return
    }
    openPanel(anchorX: anchorX)
  }

  func openPanel(anchorX: CGFloat?) {
    post(WHO, nil)  // solicit fresh announcements
    buildContent()
    let scr = NSScreen.main ?? NSScreen.screens.first!
    var x = anchorX ?? (scr.frame.maxX - panel.frame.width - 8)
    // sketchybar reports the item's x in device pixels on a retina display.
    if x > scr.frame.width { x /= scr.backingScaleFactor }
    x = min(max(scr.frame.minX + 4, x), scr.frame.maxX - panel.frame.width - 4)
    panel.setFrameTopLeftPoint(NSPoint(x: x, y: scr.visibleFrame.maxY - 2))
    panel.orderFrontRegardless()
    clickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      self?.lastMonitorClose = Date()
      self?.closePanel()
    }
  }

  func closePanel() {
    panel.orderOut(nil)
    if let m = clickMonitor {
      NSEvent.removeMonitor(m)
      clickMonitor = nil
    }
  }

  func buildContent() {
    let apps = runningApps()

    // Top-down order. A row's slot height follows from its type: separators
    // (NSBox) get SEP_H, everything else ROW_H.
    var items: [NSView] = []

    // Short wording on purpose: at this size the old "Screenshare Mode — hidden
    // from capture" overruns the 252pt slot, and the mode is already named by
    // the toggle row directly below.
    let header = NSTextField(
      labelWithString: screenshareMode ? "Selected apps visible" : "All apps visible")
    header.font = .systemFont(ofSize: 13, weight: .semibold)
    header.textColor = .labelColor  // full contrast: white on the dark scrim, black on the light one
    header.frame = NSRect(x: 14, y: 0, width: PANEL_W - 28, height: ROW_H)
    items.append(header)

    let modeRow = HoverRow("Screenshare Mode", mark: .check(screenshareMode))
    modeRow.onClick = { [weak self] in
      guard let self else { return }
      setScreenshareMode(!screenshareMode)
      buildContent()
    }
    items.append(modeRow)

    if screenshareMode {
      var nameCount = [String: Int]()
      for a in apps { nameCount[a.localizedName ?? "", default: 0] += 1 }

      items.append(separatorBox())
      // Reveal specific apps to present; everything else stays hidden.
      for app in apps {
        let pid = app.processIdentifier
        let row: HoverRow
        if let label = labels[pid] {
          row = HoverRow(label, icon: app.icon, mark: .check(revealed.contains(pid)))
          row.onClick = { [weak self, weak row] in
            guard let self else { return }
            toggle(pid)
            row?.setChecked(revealed.contains(pid))
          }
        } else {
          // No agent in this process — hiding would silently fail. Say so.
          let name = app.localizedName ?? app.bundleIdentifier!
          let dup = (nameCount[app.localizedName ?? ""] ?? 0) > 1
          row = HoverRow(
            dup ? "\(name) (\(pid))" : name, icon: app.icon, subtitle: "restart to enable",
            mark: .warning, enabled: false)
        }
        items.append(row)
      }
      items.append(separatorBox())
      for (label, action) in [
        ("Reveal All", #selector(revealAll)), ("Hide All", #selector(hideAll)),
      ] {
        let row = HoverRow(label)
        row.onClick = { [weak self] in self?.perform(action) }
        items.append(row)
      }
    }

    items.append(separatorBox())
    let quitRow = HoverRow("Quit hidewin")
    quitRow.onClick = { [weak self] in self?.quit() }
    items.append(quitRow)

    let height = PANEL_PAD * 2 + items.reduce(0) { $0 + ($1 is NSBox ? SEP_H : ROW_H) }
    let container = PanelBackground(frame: NSRect(x: 0, y: 0, width: PANEL_W, height: height))
    var y = PANEL_PAD
    for v in items {
      let sep = v is NSBox
      v.setFrameOrigin(
        NSPoint(x: v === header ? 14 : PANEL_PAD, y: sep ? y + (SEP_H - 1) / 2 : y))
      container.addSubview(v)
      y += sep ? SEP_H : ROW_H
    }

    panel.setContentSize(NSSize(width: PANEL_W, height: height))
    let backdrop = glassBackdrop(NSRect(x: 0, y: 0, width: PANEL_W, height: height), container)
    panel.contentView = backdrop
    // The glass layer tree only exists after layout, so soften afterwards.
    DispatchQueue.main.async { Controller.reduceGlassBlur(backdrop) }
  }

  // Stock glass blurs the backdrop at inputBlurRadius 10 (on a half-scale
  // backdrop), which smears whatever is behind the panel into mush. Nothing on
  // NSGlassEffectView exposes the radius, so we reach into its layer tree and
  // rebuild the private `glassBackground` CAFilter with a smaller one, copying
  // every other input verbatim. Mutating the committed filter in place does
  // nothing (it's already handed to the render server) — it has to be built
  // fresh and reassigned.
  // ponytail: private CoreAnimation API; a macOS update can rename the filter or
  // its inputs. It fails soft — no filter found means stock blur, nothing worse.
  static func reduceGlassBlur(_ view: NSView, radius: Double = 3) {
    guard let root = view.layer,
      let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    else { return }

    func visit(_ layer: CALayer) {
      defer { layer.sublayers?.forEach(visit) }
      guard String(describing: type(of: layer)) == "CABackdropLayer",
        let filters = (layer as NSObject).value(forKey: "filters") as? [NSObject]
      else { return }
      var rebuilt: [NSObject] = []
      for filter in filters {
        guard "\(filter)" == "glassBackground",
          let fresh = (filterClass as AnyObject).perform(
            NSSelectorFromString("filterWithName:"), with: "glassBackground")?
            .takeUnretainedValue() as? NSObject,
          let inputs = filter.perform(NSSelectorFromString("inputKeys"))?
            .takeUnretainedValue() as? [String]
        else {
          rebuilt.append(filter)
          continue
        }
        for key in inputs where key != "inputBlurRadius" {
          if let v = filter.value(forKey: key) { fresh.setValue(v, forKey: key) }
        }
        fresh.setValue(radius, forKey: "inputBlurRadius")
        rebuilt.append(fresh)
      }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      (layer as NSObject).setValue(rebuilt, forKey: "filters")
      CATransaction.commit()
    }
    visit(root)
  }

  // Liquid Glass (macOS 26 NSGlassEffectView), resolved at RUNTIME: the nixpkgs
  // Swift SDK predates the class, so we can't name it at compile time. Falls
  // back to the old vibrancy material on anything older.
  //
  // style 1 = .clear. The default (.regular, 0) lays a heavy scrim over the
  // backdrop and reads like plain vibrancy; .clear lets the colors behind
  // actually come through. Verified side by side against a test pattern.
  func glassBackdrop(_ frame: NSRect, _ content: NSView) -> NSView {
    if let cls = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
      let glass = cls.init() as? NSView
    {
      glass.frame = frame
      glass.setValue(1, forKey: "style")
      glass.setValue(PANEL_RADIUS, forKey: "cornerRadius")
      glass.setValue(content, forKey: "contentView")
      return glass
    }
    let vev = NSVisualEffectView(frame: frame)
    vev.material = .menu
    vev.state = .active
    vev.blendingMode = .behindWindow
    vev.wantsLayer = true
    vev.layer?.cornerRadius = 8
    vev.layer?.masksToBounds = true
    vev.addSubview(content)
    return vev
  }

  func toggle(_ pid: pid_t) {
    if revealed.contains(pid) {
      revealed.remove(pid)
      post(HIDE, String(pid))
    } else {
      revealed.insert(pid)
      post(SHOW, String(pid))
    }
  }

  @objc func revealAll() {
    // Only apps with an injected agent can actually be revealed.
    revealed = Set(runningApps().map { $0.processIdentifier }.filter { labels[$0] != nil })
    post(SHOW, nil)
    buildContent()
  }

  @objc func hideAll() {
    revealed = []
    post(HIDE, nil)
    buildContent()
  }

  @objc func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
