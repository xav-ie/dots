// airpods-mode — set AirPods listening mode (ANC / Transparency / Off) on macOS,
// and a --daemon that flips it on media play/pause (play→ANC, pause→Transparency).
//
// How (setting the mode): macOS's bluetoothd holds the single AACP control
// channel to the AirPods (PSM 0x1001), so a third-party process can't open its
// own L2CAP channel — the open is refused (kIOReturnError). Instead we go through
// the same private AVFoundation path Control Center uses:
// AVOutputContext's shared system-audio context gives the current AVOutputDevice,
// whose -setCurrentBluetoothListeningMode:error: routes the change through the
// system's existing channel.
//
// How (detecting play/pause): the private MediaRemote framework, dlopen'd at
// runtime. MRMediaRemoteRegisterForNowPlayingNotifications + the
// IsPlayingDidChange notification + MRMediaRemoteGetNowPlayingApplicationIsPlaying.
//
// AVOutputContext/AVOutputDevice and MediaRemote symbols aren't Swift-visible, so
// we reach them through the Obj-C runtime / dlsym. Mirrors NoiseBuddy's
// NCAVListeningModeController.
//
// Gating (both honored because this machine boots amfi_get_out_of_my_way=1, via
// airpods-mode.entitlements): the shared system-audio context needs
// com.apple.avfoundation.allow-system-wide-context; IOBluetooth/Bluetooth and
// MediaRemote reads need their respective grants.
//
// Usage:
//   airpods-mode list                      list output devices + their modes
//   airpods-mode off | anc | transparency | adaptive
//   airpods-mode --device "AirPods" anc    target a specific output device by name
//   airpods-mode --verbose <mode>          log the before/after mode
//   airpods-mode --daemon                  flip mode on media play/pause

import AVFoundation  // links the framework so NSClassFromString resolves AVOutputContext
import Foundation

let ANC = "AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation"
let TRANSPARENCY = "AVOutputDeviceBluetoothListeningModeAudioTransparency"

func die(_ msg: String, _ code: Int32 = 1) -> Never {
  fputs("airpods-mode: \(msg)\n", stderr)
  exit(code)
}

// Map a CLI command to the AVOutputDevice listening-mode identifier.
func avModeString(_ command: String) -> String? {
  switch command {
  case "off", "normal", "none": return "AVOutputDeviceBluetoothListeningModeNormal"
  case "anc", "nc", "noise-cancellation": return ANC
  case "transparency", "transparent", "trans": return TRANSPARENCY
  // The AirPods Pro "Adaptive" mode reports as ...Automatic in availableModes.
  case "adaptive", "automatic", "auto": return "AVOutputDeviceBluetoothListeningModeAutomatic"
  default: return nil
  }
}

// MARK: - AVOutputDevice access (via the Obj-C runtime)

func deviceName(_ d: AnyObject) -> String { (d.value(forKey: "name") as? String) ?? "?" }
func currentMode(_ d: AnyObject) -> String {
  (d.value(forKey: "currentBluetoothListeningMode") as? String) ?? ""
}
func availableModes(_ d: AnyObject) -> [String] {
  (d.value(forKey: "availableBluetoothListeningModes") as? [String]) ?? []
}

func sharedAudioContext() -> AnyObject? {
  guard let cls = NSClassFromString("AVOutputContext") else { return nil }
  let clsObj = cls as AnyObject
  for selName in ["sharedSystemAudio", "sharedSystemAudioContext"] {
    let sel = NSSelectorFromString(selName)
    if clsObj.responds(to: sel) { return clsObj.perform(sel)?.takeUnretainedValue() }
  }
  return nil
}

// Fetched fresh each call so the daemon tracks output-device changes.
func outputDevices() -> [AnyObject] {
  (sharedAudioContext()?.value(forKey: "outputDevices") as? [AnyObject]) ?? []
}

@discardableResult
func applyMode(_ modeString: String, hint: String, verbose: Bool) -> Bool {
  let devices = outputDevices()
  guard
    let device = devices.first(where: { deviceName($0).localizedCaseInsensitiveContains(hint) })
      ?? devices.first
  else {
    if verbose { fputs("applyMode: no output device\n", stderr) }
    return false
  }
  let sel = NSSelectorFromString("setCurrentBluetoothListeningMode:error:")
  guard device.responds(to: sel) else {
    if verbose { fputs("applyMode: device has no setCurrentBluetoothListeningMode:\n", stderr) }
    return false
  }
  _ = device.perform(sel, with: modeString, with: nil)
  if verbose {
    fputs("set \(deviceName(device)) → \(modeString); now=\(currentMode(device))\n", stderr)
  }
  return true
}

// MARK: - MediaRemote play/pause daemon

// In-process MediaRemote works only when the process's bundle id starts with
// com.apple. (mediaremoted's access gate). We sign the daemon with such an id —
// possible only under amfi_get_out_of_my_way=1. Otherwise reads wedge on play.
func runDaemon(hint: String, verbose: Bool) -> Never {
  typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
  typealias IsPlayingFn = @convention(c) (
    DispatchQueue, @escaping @convention(block) (Bool) -> Void
  )
    -> Void

  guard
    let mr = dlopen(
      "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
    let regSym = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications"),
    let playSym = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
  else { die("MediaRemote load failed") }

  let register = unsafeBitCast(regSym, to: RegisterFn.self)
  let getIsPlaying = unsafeBitCast(playSym, to: IsPlayingFn.self)
  let q = DispatchQueue(label: "codes.x.airpods-mode.mr")
  register(q)

  var last: Bool?
  func handle(_ playing: Bool) {
    if playing == last { return }
    last = playing
    applyMode(playing ? ANC : TRANSPARENCY, hint: hint, verbose: verbose)
    fputs("airpods-mode: \(playing ? "play → ANC" : "pause → transparency")\n", stderr)
  }
  // Read now-playing state and act; always lands on q (serial → no races on `last`).
  func refresh() { getIsPlaying(q) { handle($0) } }

  // Event-driven: mediaremoted posts this on every play/pause transition and we
  // react immediately. Delivery works because our com.apple.* bundle id passes
  // mediaremoted's now-playing access gate (registered via register(q) above).
  NotificationCenter.default.addObserver(
    forName: NSNotification.Name(
      "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
    object: nil, queue: nil
  ) { _ in q.async { refresh() } }

  // Sync current state once at startup (e.g. if media is already playing).
  refresh()

  fputs("airpods-mode: daemon watching media play/pause (MediaRemote)\n", stderr)
  dispatchMain()
}

// MARK: - CLI parsing

var args = Array(CommandLine.arguments.dropFirst())
var verbose = false
var deviceHint: String?
var positional: [String] = []

var i = 0
while i < args.count {
  switch args[i] {
  case "--verbose", "-v": verbose = true
  case "--daemon": positional.append("daemon")
  case "--device", "-d":
    i += 1
    guard i < args.count else { die("--device needs a name") }
    deviceHint = args[i]
  default: positional.append(args[i])
  }
  i += 1
}

guard let command = positional.first else {
  die(
    "usage: airpods-mode [--device NAME] [--verbose] "
      + "list | off | anc | transparency | adaptive | --daemon", 2)
}

let hint = deviceHint ?? "AirPods"

if command == "daemon" {
  runDaemon(hint: hint, verbose: verbose)
}

if command == "list" {
  let devices = outputDevices()
  if devices.isEmpty { die("no system output devices (missing avfoundation entitlement?)") }
  for d in devices {
    let modes = availableModes(d)
    let cur = currentMode(d)
    print("\(deviceName(d))")
    print("    current:   \(cur.isEmpty ? "—" : cur)")
    print("    available: \(modes.isEmpty ? "—" : modes.joined(separator: ", "))")
  }
  exit(0)
}

guard let modeString = avModeString(command) else {
  die("unknown mode '\(command)' (use: off | anc | transparency | adaptive)", 2)
}

if verbose {
  let devices = outputDevices()
  if let device = devices.first(where: { deviceName($0).localizedCaseInsensitiveContains(hint) })
    ?? devices.first
  {
    fputs(
      "device: \(deviceName(device)); current=\(currentMode(device)); "
        + "available=[\(availableModes(device).joined(separator: ", "))]\n", stderr)
  }
}

guard applyMode(modeString, hint: hint, verbose: verbose) else {
  die("no matching output device (try: airpods-mode list)")
}
