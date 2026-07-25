// hidewin-bar — menubar manager for capture-hidden apps.
//
// Windows are VISIBLE by default (so recorders like Dayflow keep working).
// This menubar app's "Screenshare Mode" hides everything from capture for
// a meeting; you then reveal the specific apps you want to present. The
// eye/eye.slash icon shows whether Screenshare Mode is active.
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
// posting the toggle below with the item's x so we place the panel under it.
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

// Top-down layout so the app list reads like a menu.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

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
  private var markTint: NSColor = .labelColor
  private var markIsCheck = false
  private let enabled: Bool
  private var track: NSTrackingArea?

  init(
    width: CGFloat, height: CGFloat, icon: NSImage?, title: String, subtitle: String?, mark m: Mark,
    enabled: Bool
  ) {
    self.enabled = enabled
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    wantsLayer = true
    layer?.cornerRadius = 5

    var x: CGFloat = 8
    mark.frame = NSRect(x: x, y: (height - 13) / 2, width: 13, height: 13)
    switch m {
    case .check(let on):
      markIsCheck = true
      mark.image = on ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
    case .warning:
      markTint = .systemOrange
      mark.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
    case .none:
      break
    }
    mark.contentTintColor = markTint
    addSubview(mark)
    x += 20

    if let icon = icon {
      icon.size = NSSize(width: 16, height: 16)
      let iv = NSImageView(frame: NSRect(x: x, y: (height - 16) / 2, width: 16, height: 16))
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
    label.frame = NSRect(x: x, y: (height - 16) / 2, width: width - x - 8, height: 16)
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }

  func setChecked(_ on: Bool) {
    mark.image = on ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
    mark.contentTintColor = markTint
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let t = track { removeTrackingArea(t) }
    let t = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
    addTrackingArea(t)
    track = t
  }
  override func mouseEntered(with event: NSEvent) {
    layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
    label.textColor = .white
    if markIsCheck { mark.contentTintColor = .white }
  }
  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = NSColor.clear.cgColor
    label.textColor = enabled ? .labelColor : .secondaryLabelColor
    mark.contentTintColor = markTint
  }
  override func mouseDown(with event: NSEvent) {}  // claim the event so mouseUp fires
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}

final class Controller: NSObject {
  let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
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

    // The sketchybar plugin's mouse.clicked runs `hidewin panel <x>`, posting
    // this with the item's x so we place the panel under it.
    DistributedNotificationCenter.default().addObserver(
      forName: TOGGLE, object: nil, queue: .main
    ) { [weak self] note in
      let x = (note.object as? String).flatMap(Double.init).map { CGFloat($0) }
      self?.togglePanel(anchorX: x)
    }

    DistributedNotificationCenter.default().addObserver(
      forName: IAM, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, let s = note.object as? String else { return }
      let parts = s.components(separatedBy: "\t")
      guard parts.count == 2, let pid = pid_t(parts[0]) else { return }
      // Refresh when a pid first proves it's injected (⚠ → checkbox) OR when its
      // label improves (e.g. Firefox's "— Work" suffix set once a window is key).
      let changed = self.labels[pid] != parts[1]
      self.labels[pid] = parts[1]
      if changed && self.panel.isVisible { self.buildContent() }
    }
    post(WHO, nil)
    // Fail safe: if we were hiding when last quit (e.g. crashed mid-meeting),
    // restore that state rather than silently un-hiding.
    if UserDefaults.standard.bool(forKey: "screenshareMode") {
      setScreenshareMode(true)
    } else {
      publishMode()  // write initial state for the sketchybar plugin
    }
  }

  // The master toggle. ON hides everything (except already-revealed apps) and
  // keeps new apps hidden as they launch; OFF makes everything visible again.
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
          guard let self = self, self.screenshareMode,
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
          else { return }
          if !self.revealed.contains(app.processIdentifier) {
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
    let W: CGFloat = 280
    let pad: CGFloat = 6
    let rowH: CGFloat = 24
    let sepH: CGFloat = 9
    let rowW = W - pad * 2
    let apps = runningApps()
    var nameCount = [String: Int]()
    for a in apps { nameCount[a.localizedName ?? "", default: 0] += 1 }

    // (view, slotHeight) in top-down order.
    var items: [(NSView, CGFloat)] = []

    let header = NSTextField(
      labelWithString: screenshareMode
        ? "Screenshare Mode — hidden from capture" : "Normal — all apps visible")
    header.font = .systemFont(ofSize: 11, weight: .semibold)
    header.textColor = .secondaryLabelColor
    header.frame = NSRect(x: 14, y: 0, width: W - 28, height: rowH)
    items.append((header, rowH))

    // Master toggle.
    let modeRow = HoverRow(
      width: rowW, height: rowH, icon: nil, title: "Screenshare Mode", subtitle: nil,
      mark: .check(screenshareMode), enabled: true)
    modeRow.onClick = { [weak self] in
      guard let self = self else { return }
      self.setScreenshareMode(!self.screenshareMode)
      self.buildContent()
    }
    items.append((modeRow, rowH))
    items.append((separatorBox(rowW), sepH))

    if screenshareMode {
      // Reveal specific apps to present; everything else stays hidden.
      for app in apps {
        let pid = app.processIdentifier
        let injected = labels[pid] != nil
        let base = labels[pid] ?? app.localizedName ?? app.bundleIdentifier!
        var title = base
        if !injected && (nameCount[app.localizedName ?? ""] ?? 0) > 1 { title = "\(base) (\(pid))" }
        let row: HoverRow
        if injected {
          row = HoverRow(
            width: rowW, height: rowH, icon: app.icon, title: title, subtitle: nil,
            mark: .check(revealed.contains(pid)), enabled: true)
          row.onClick = { [weak self, weak row] in
            guard let self = self else { return }
            self.toggle(pid)
            row?.setChecked(self.revealed.contains(pid))
          }
        } else {
          // No agent in this process — hiding would silently fail. Say so.
          row = HoverRow(
            width: rowW, height: rowH, icon: app.icon, title: title, subtitle: "restart to enable",
            mark: .warning, enabled: false)
          row.onClick = nil
        }
        items.append((row, rowH))
      }
      items.append((separatorBox(rowW), sepH))
      for (label, action) in [
        ("Reveal All", #selector(revealAll)), ("Hide All", #selector(hideAll)),
      ] {
        let row = HoverRow(
          width: rowW, height: rowH, icon: nil, title: label, subtitle: nil, mark: .none,
          enabled: true)
        row.onClick = { [weak self] in self?.perform(action) }
        items.append((row, rowH))
      }
    } else {
      let note = HoverRow(
        width: rowW, height: rowH, icon: nil,
        title: "Turn on before a meeting to hide apps", subtitle: nil, mark: .none, enabled: false)
      items.append((note, rowH))
    }

    items.append((separatorBox(rowW), sepH))
    let quitRow = HoverRow(
      width: rowW, height: rowH, icon: nil, title: "Quit hidewin", subtitle: nil, mark: .none,
      enabled: true)
    quitRow.onClick = { [weak self] in self?.quit() }
    items.append((quitRow, rowH))

    let height = pad * 2 + items.reduce(0) { $0 + $1.1 }
    let container = FlippedView(frame: NSRect(x: 0, y: 0, width: W, height: height))
    var y = pad
    for (v, h) in items {
      if v is NSBox {
        v.setFrameOrigin(NSPoint(x: pad, y: y + (h - 1) / 2))
      } else if v === header {
        v.setFrameOrigin(NSPoint(x: 14, y: y + (h - rowH) / 2))
      } else {
        v.setFrameOrigin(NSPoint(x: pad, y: y))
      }
      container.addSubview(v)
      y += h
    }

    let vev = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: W, height: height))
    vev.material = .menu
    vev.state = .active
    vev.blendingMode = .behindWindow
    vev.wantsLayer = true
    vev.layer?.cornerRadius = 8
    vev.layer?.masksToBounds = true
    vev.addSubview(container)
    panel.setContentSize(NSSize(width: W, height: height))
    panel.contentView = vev
  }

  func separatorBox(_ width: CGFloat) -> NSBox {
    let v = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    v.boxType = .separator
    return v
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
