import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// AX window model
//
// focusd manages window focus itself through the Accessibility API. AX exposes
// no public stable window id, so we read each window's CGWindowID via the private
// _AXUIElementGetWindow (the same handle yabai uses): it is stable for a window's
// lifetime and ascends with creation, giving a deterministic cycle order that
// doesn't shift as z-order churns.

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>)
  -> AXError

struct AXWin {
  let el: AXUIElement
  let pid: pid_t
  let wid: CGWindowID
  let title: String
}

func axString(_ el: AXUIElement, _ attr: String) -> String? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
  return v as? String
}

func axBool(_ el: AXUIElement, _ attr: String) -> Bool {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return false }
  return (v as? Bool) ?? false
}

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let r = v,
    CFGetTypeID(r) == AXUIElementGetTypeID()
  else { return nil }
  return (r as! AXUIElement)
}

func axWindowID(_ el: AXUIElement) -> CGWindowID? {
  var wid = CGWindowID(0)
  return _AXUIElementGetWindow(el, &wid) == .success ? wid : nil
}

func axCGSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
    let val = v, CFGetTypeID(val) == AXValueGetTypeID()
  else { return nil }
  var size = CGSize.zero
  AXValueGetValue(val as! AXValue, .cgSize, &size)
  return size
}

func axCGPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
    let val = v, CFGetTypeID(val) == AXValueGetTypeID()
  else { return nil }
  var pt = CGPoint.zero
  AXValueGetValue(val as! AXValue, .cgPoint, &pt)
  return pt
}

// Yabai window model (cross-Space lookup only)
//
// yabai enumerates via SkyLight, so unlike AX it sees windows on every Space —
// the one thing we need it for: which Space a window lives on, so we can switch
// to it. `id` is the CGWindowID, matching axWindowID above.

struct YWindow: Decodable {
  let id: Int
  let pid: Int
  let space: Int
  let title: String
}

func fetchYabaiWindows() -> [YWindow] {
  let (status, out) = run(resolve(YABAI), ["-m", "query", "--windows"])
  guard status == 0 else { return [] }
  return (try? JSONDecoder().decode([YWindow].self, from: out)) ?? []
}
