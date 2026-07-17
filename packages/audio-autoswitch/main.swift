import CoreAudio
import Foundation

// Event-driven default-output switcher for USB EarPods (macOS won't auto-select
// them). Listens on the device list and, on the absent -> present transition,
// makes the target the default output — so manually picking speakers while
// plugged in is respected until you unplug and replug.

setbuf(stdout, nil)  // daemon: flush log lines as they happen

let targetName = ProcessInfo.processInfo.environment["AUDIO_AUTOSWITCH_DEVICE"] ?? "EarPods"

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func address(
  _ selector: AudioObjectPropertySelector,
  _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
)
  -> AudioObjectPropertyAddress
{
  AudioObjectPropertyAddress(
    mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func allDevices() -> [AudioDeviceID] {
  var addr = address(kAudioHardwarePropertyDevices)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else {
    return []
  }
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else {
    return []
  }
  return ids
}

func name(_ id: AudioDeviceID) -> String? {
  var addr = address(kAudioObjectPropertyName)
  var size = UInt32(MemoryLayout<CFString?>.size)
  var cf: CFString?
  guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr else { return nil }
  return cf as String?
}

func hasOutput(_ id: AudioDeviceID) -> Bool {
  var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
    return false
  }
  let raw = UnsafeMutableRawPointer.allocate(
    byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
  defer { raw.deallocate() }
  guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
  let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
  return list.contains { $0.mNumberChannels > 0 }
}

func defaultOutput() -> AudioDeviceID {
  var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
  var id = AudioDeviceID(0)
  var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id)
  return id
}

func setDefaultOutput(_ id: AudioDeviceID) {
  var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
  var dev = id
  let status = AudioObjectSetPropertyData(
    systemObject, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
  if status != noErr {
    FileHandle.standardError.write("set default failed: \(status)\n".data(using: .utf8)!)
  }
}

var lastPresent = false

func evaluate() {
  let target = allDevices().first { hasOutput($0) && name($0) == targetName }
  let present = target != nil
  if present, !lastPresent, defaultOutput() != target! {
    setDefaultOutput(target!)
    print("switched default output to \(targetName)")
  }
  lastPresent = present
}

var addr = address(kAudioHardwarePropertyDevices)
let status = AudioObjectAddPropertyListenerBlock(systemObject, &addr, DispatchQueue.main) { _, _ in
  evaluate()
}
if status != noErr {
  FileHandle.standardError.write("failed to register listener: \(status)\n".data(using: .utf8)!)
  exit(1)
}

evaluate()  // handle already-plugged at start
dispatchMain()
