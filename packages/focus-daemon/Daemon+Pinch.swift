import AppKit
import CoreGraphics
import Foundation

// Trackpad pinch → PiP resize, via the raw trackpad (private MultitouchSupport).
//
// A trackpad pinch can't be seen from inside Firefox (macOS routes magnify
// gestures only to the frontmost app, never as a background DOM event), and — as
// this repo learned the hard way — a session CGEventTap on magnify events is
// silently starved in a launchd-agent context: created + permissioned + enabled
// yet zero delivery, and even when it delivers, NSEvent(cgEvent:) fails to decode
// the magnification ("unrecognized type is 30"). So we go under all of that and
// read the trackpad HID directly, the way BetterTouchTool does: MultitouchSupport
// gives us raw finger positions in every frame, from which we recognize a pinch
// ourselves and forward a per-frame scale delta + cursor point to the PiP's
// `pinch` UDP command. firefox-pip-mover gates on cursor-over-PiP (it knows the
// exact bounds) and scales about the cursor.
//
// Reading the trackpad needs Input Monitoring (granted to focusd in _nox-body).

private typealias MTDeviceRef = UnsafeMutableRawPointer
// (device, touches, numTouches, timestamp, frame) — touches is an array of the
// private MTTouch struct; we read only what we need via byte offsets so the
// callback stays @convention(c)-representable (a typed struct pointer isn't).
private typealias MTContactCallback =
  @convention(c) (
    Int32, UnsafeRawPointer?, Int32, Double, Int32
  ) -> Int32

// MTTouch layout (stable across many OS versions): normalized.position is two
// Floats at byte offset 32; the struct stride is 0x60. We only touch those.
private let MT_STRIDE = 96
private let MT_NORM_X = 32
private let MT_NORM_Y = 36

private var mtPrevDist: Float = -1  // -1 = no active 2-finger gesture
private var mtPrevMidX: Float = 0  // previous two-finger midpoint, to tell pinch from slide
private var mtPrevMidY: Float = 0
private var mtMode = 0  // this gesture: 0 = undecided, 1 = pinch, 2 = slide (Firefox's job)
private var mtAccDist: Float = 0  // cumulative separation change / midpoint travel, for the
private var mtAccMid: Float = 0  // one-time pinch-vs-slide decision
private let MT_DECIDE: Float = 0.03  // finger travel to accumulate before locking the mode
private var pinchSock: Int32 = -1  // reused UDP datagram socket to the PiP listener

// The MT device dies silently across sleep/wake (and USB trackpad replug): the
// handle stays valid, the callback just stops firing forever. So the handle is
// re-openable — mtClose() fully tears the old one down (stop, unregister, release)
// before mtOpen() creates a new one, so a re-open costs nothing in memory.
private var mtDev: MTDeviceRef? = nil
private var mtCreate: (@convention(c) () -> MTDeviceRef?)? = nil
private var mtRegister: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void)? = nil
private var mtUnregister: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void)? = nil
private var mtStart: (@convention(c) (MTDeviceRef, Int32) -> Void)? = nil
private var mtStop: (@convention(c) (MTDeviceRef) -> Void)? = nil
private var mtRelease: (@convention(c) (MTDeviceRef) -> Void)? = nil
private var mtIsRunning: (@convention(c) (MTDeviceRef) -> Bool)? = nil

private let mtCallback: MTContactCallback = { _, touches, n, _, _ in
  onTouchFrame(touches, n)
  return 0
}

private func mtResolve() -> Bool {
  if mtCreate != nil { return true }
  let path =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
  guard let h = dlopen(path, RTLD_NOW) else {
    fputs("focusd: MultitouchSupport dlopen failed\n", stderr)
    return false
  }
  guard let pDefault = dlsym(h, "MTDeviceCreateDefault"),
    let pReg = dlsym(h, "MTRegisterContactFrameCallback"),
    let pStart = dlsym(h, "MTDeviceStart")
  else {
    fputs("focusd: MultitouchSupport dlsym failed\n", stderr)
    return false
  }
  mtCreate = unsafeBitCast(pDefault, to: (@convention(c) () -> MTDeviceRef?).self)
  mtRegister = unsafeBitCast(
    pReg, to: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
  mtStart = unsafeBitCast(pStart, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
  // Teardown/liveness symbols: present on every OS we've seen, but optional —
  // without them we degrade to leaking one device per re-open rather than failing.
  if let p = dlsym(h, "MTUnregisterContactFrameCallback") {
    mtUnregister = unsafeBitCast(
      p, to: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
  }
  if let p = dlsym(h, "MTDeviceStop") {
    mtStop = unsafeBitCast(p, to: (@convention(c) (MTDeviceRef) -> Void).self)
  }
  if let p = dlsym(h, "MTDeviceRelease") {
    mtRelease = unsafeBitCast(p, to: (@convention(c) (MTDeviceRef) -> Void).self)
  }
  if let p = dlsym(h, "MTDeviceIsRunning") {
    mtIsRunning = unsafeBitCast(p, to: (@convention(c) (MTDeviceRef) -> Bool).self)
  }
  return true
}

private func mtClose() {
  guard let dev = mtDev else { return }
  mtDev = nil
  mtStop?(dev)
  mtUnregister?(dev, mtCallback)
  if let release = mtRelease {
    release(dev)
  } else {
    Unmanaged<AnyObject>.fromOpaque(dev).release()  // MTDeviceRef is a CF type
  }
  mtPrevDist = -1  // any in-flight gesture is over
}

private func mtOpen() {
  mtClose()
  guard mtResolve(), let create = mtCreate, let dev = create() else {
    fputs("focusd: no multitouch device\n", stderr)
    return
  }
  mtDev = dev
  mtRegister?(dev, mtCallback)
  mtStart?(dev, 0)
  fputs("focusd: multitouch pinch capture started\n", stderr)
}

extension Daemon {
  func startPinchCapture() {
    if pinchSock < 0 { pinchSock = socket(AF_INET, SOCK_DGRAM, 0) }
    mtOpen()
    // Wake is the known killer; re-open there. The 60s poll is the backstop for
    // every other way the device goes quiet (replug, display wake without a
    // system wake) — MTDeviceIsRunning is cheap and re-opens only when dead, so
    // the steady state allocates nothing.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in mtOpen() }
    Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
      guard let dev = mtDev, let running = mtIsRunning else { return }
      if !running(dev) {
        fputs("focusd: multitouch device stopped — reopening\n", stderr)
        mtOpen()
      }
    }
  }
}

// Recognize a two-finger pinch from raw finger positions and forward the frame's
// scale delta. A pinch is a change in the distance between two fingers; we emit
// (dist - prevDist) * gain and let the far side apply size *= (1 + delta).
private func onTouchFrame(_ touches: UnsafeRawPointer?, _ n: Int32) {
  guard let base = touches, n >= 2 else {
    mtPrevDist = -1  // gesture ended / not two fingers — reseed next time
    mtMode = 0
    mtAccDist = 0
    mtAccMid = 0
    return
  }
  let x0 = base.loadUnaligned(fromByteOffset: MT_NORM_X, as: Float.self)
  let y0 = base.loadUnaligned(fromByteOffset: MT_NORM_Y, as: Float.self)
  let x1 = base.loadUnaligned(fromByteOffset: MT_STRIDE + MT_NORM_X, as: Float.self)
  let y1 = base.loadUnaligned(fromByteOffset: MT_STRIDE + MT_NORM_Y, as: Float.self)
  let dx = x0 - x1
  let dy = y0 - y1
  let dist = (dx * dx + dy * dy).squareRoot()
  let midX = (x0 + x1) / 2
  let midY = (y0 + y1) / 2

  let prevDist = mtPrevDist
  let prevMidX = mtPrevMidX
  let prevMidY = mtPrevMidY
  mtPrevDist = dist
  mtPrevMidX = midX
  mtPrevMidY = midY
  if prevDist < 0 { return }  // first frame of a gesture: seed only

  // Pinch vs two-finger slide: a pinch changes the fingers' SEPARATION; a slide
  // translates their MIDPOINT (and a slide is Firefox's scroll-to-move). Decide
  // ONCE per gesture from accumulated travel, then commit — a per-frame test drops
  // pinch frames whenever the hand drifts, which stutters the resize.
  let distChange = abs(dist - prevDist)
  let mdx = midX - prevMidX
  let mdy = midY - prevMidY
  let midMove = (mdx * mdx + mdy * mdy).squareRoot()
  if mtMode == 0 {
    mtAccDist += distChange
    mtAccMid += midMove
    if mtAccDist + mtAccMid < MT_DECIDE { return }  // not enough travel to tell yet
    mtMode = mtAccDist > mtAccMid ? 1 : 2
  }
  if mtMode != 1 { return }  // a slide — leave the move to Firefox's scroll handler

  let delta = Double(dist - prevDist) * PINCH_GAIN
  if delta == 0 { return }
  guard let loc = CGEvent(source: nil)?.location else { return }
  sendPinch(delta: delta, x: loc.x, y: loc.y)
}

private func sendPinch(delta: Double, x: CGFloat, y: CGFloat) {
  if pinchSock < 0 { return }
  let msg = "pinch \(delta) \(Double(x)) \(Double(y))"
  for port in PINCH_PORTS {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = msg.withCString { c in
      withUnsafePointer(to: &addr) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
          sendto(pinchSock, c, strlen(c), 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
  }
}
