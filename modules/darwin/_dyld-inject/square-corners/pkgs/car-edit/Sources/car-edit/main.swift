// car-edit — replace WindowShapeEdges renditions in a macOS .car asset
// catalog so window-frame masks/rims are flat (kills macOS Tahoe's 1px
// shadow-rim outline).
//
// usage:
//   car-edit <input.car> -o <output.car>

import CoreGraphics
import CoreUIBridge
import Foundation

func usage() -> Never {
  FileHandle.standardError.write(Data("usage: car-edit <input.car> -o <output.car>\n".utf8))
  exit(2)
}

let args = CommandLine.arguments
guard args.count == 4, args[2] == "-o" else { usage() }
let inputPath = args[1]
let outputPath = args[3]

if FileManager.default.fileExists(atPath: outputPath) {
  try FileManager.default.removeItem(atPath: outputPath)
}
do {
  try FileManager.default.copyItem(atPath: inputPath, toPath: outputPath)
} catch {
  FileHandle.standardError.write(
    Data("error: copy \(inputPath) -> \(outputPath) failed: \(error)\n".utf8))
  exit(1)
}

// Open both views: read-side catalog (for the named-lookup table) and
// write-side mutable storage (for replacement).
let catalog: CUICatalog
do {
  catalog = try CUICatalog(url: URL(fileURLWithPath: outputPath))
} catch {
  FileHandle.standardError.write(Data("error: could not open catalog: \(error)\n".utf8))
  exit(1)
}
let themeStore = catalog._themeStore()

guard let storage = CUIMutableCommonAssetStorage(path: outputPath, forWriting: true) else {
  FileHandle.standardError.write(Data("error: could not open storage for writing\n".utf8))
  exit(1)
}

// pixelFormat fourcc constants (big-endian Int32).
//   ARGB = the visible rim color → we want fully transparent (no rim).
//   GA8  = the shape-mask. The ZimengXiong / Shiqi Mei recipe fills it with
//          `graya(255, 0.54902)` (white at ~55% alpha):
//            https://shiqimei.github.io/posts/macos-square-corners.html
//          A fully-opaque fill (alpha 1.0) renders as a solid white bar.
//
// NOTE (macOS 26.5.x): even the faithful 0.54902 recipe now renders the
// 9-patch top-edge slice as a translucent bar across the window top. The
// underlying WindowShapeEdges asset bytes are byte-identical to earlier
// Tahoe builds, so this is a WindowServer compositing change, not a data
// change — the published recipe has no fix yet. kGA8Fill* below is the knob.
let kFormatARGB: Int32 = 0x4152_4742
let kFormatGA8: Int32 = 0x4741_3820

// GA8 shape-mask fill (grayscale white + alpha).
//
// The published ZimengXiong / Shiqi Mei recipe fills it graya(255, 0.54902).
// That worked through earlier Tahoe builds, but macOS 26.5.x changed how
// WindowServer composites this rendition: instead of an invisible clip, it
// *draws* the 9-patch top-edge slice, so any opaque fill paints a band across
// the window top (0.54902 → translucent gray bar, 1.0 → solid white bar). The
// underlying asset bytes are byte-identical to older builds, so this is purely
// a compositor change.
//
// FIX (verified on 26.5.1): fill the shape mask fully TRANSPARENT (alpha 0).
// With no opaque slice there is nothing to draw, and the NSThemeFrame dylib
// (../macos-corner-fix) already squares the corners — an empty WindowShapeEdges
// mask yields a rectangular window with no top bar. If a future build rounds
// the corners again with an empty mask, the mask is back to being the clip and
// the value to revisit is kGA8FillAlpha (the legacy recipe used 0.54902).
let kGA8FillGray: CGFloat = 1.0
let kGA8FillAlpha: CGFloat = 0.0

// Debug: print an ASCII map of the rendition's alpha (and gray) channels so
// we can see the actual mask shape instead of guessing. ' '=transparent,
// '.'<low '+'<mid '#'=opaque. Gated by CAR_EDIT_DUMP.
func dumpAlphaMap(_ rendition: CUIThemeRendition) {
  guard let unmanaged = rendition.unslicedImage() else {
    print("dump \(rendition.name()): no image")
    return
  }
  let image = unmanaged.takeUnretainedValue()
  let w = image.width
  let h = image.height
  var buf = [UInt8](repeating: 0, count: w * h * 4)
  guard
    let ctx = CGContext(
      data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return }
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
  print("dump \(rendition.name()) \(w)x\(h)  alpha map:")
  for y in 0..<h {
    var row = "  "
    for x in 0..<w {
      let a = buf[(y * w + x) * 4 + 3]
      switch a {
      case 0: row += " "
      case 1..<85: row += "."
      case 85..<200: row += "+"
      default: row += "#"
      }
    }
    print(row)
  }
}

func makeReplacementBitmap(
  width: UInt32, height: UInt32, pixelFormat: Int32
) -> CSIBitmapWrapper? {
  guard let wrapper = CSIBitmapWrapper(pixelWidth: width, pixelHeight: height) else { return nil }
  let ctx = wrapper.bitmapContext().takeUnretainedValue()
  let rect = CGRect(x: 0, y: 0, width: Int(width), height: Int(height))
  if pixelFormat == kFormatGA8 {
    ctx.setFillColor(
      CGColor(red: kGA8FillGray, green: kGA8FillGray, blue: kGA8FillGray, alpha: kGA8FillAlpha))
    ctx.fill(rect)
  } else {
    ctx.clear(rect)
  }
  return wrapper
}

// Compute the nine 9-patch slice rects for a canvas of `size` with corner caps
// of `tl` (top-left) and `br` (bottom-right). The middle row/column gets
// stretched at render time; the four corners are unstretched.
//
//   ┌──────┬─────────────┬──────┐
//   │ tl   │ top edge    │ tr   │   tl/tr/bl/br = corner caps (unstretched)
//   ├──────┼─────────────┼──────┤
//   │ left │ center      │ right│   center/edges = stretched
//   ├──────┼─────────────┼──────┤
//   │ bl   │ bottom edge │ br   │
//   └──────┴─────────────┴──────┘
func ninePatchSliceRects(canvas size: CGSize, tl: CGSize, br: CGSize) -> [CGRect] {
  let w = size.width
  let h = size.height
  let lw = tl.width
  let lh = tl.height  // left col / top row
  let rw = br.width
  let rh = br.height  // right col / bottom row
  let mw = max(0, w - lw - rw)  // middle col
  let mh = max(0, h - lh - rh)  // middle row
  return [
    CGRect(x: 0, y: 0, width: lw, height: lh),  // top-left
    CGRect(x: lw, y: 0, width: mw, height: lh),  // top edge
    CGRect(x: lw + mw, y: 0, width: rw, height: lh),  // top-right
    CGRect(x: 0, y: lh, width: lw, height: mh),  // left edge
    CGRect(x: lw, y: lh, width: mw, height: mh),  // center
    CGRect(x: lw + mw, y: lh, width: rw, height: mh),  // right edge
    CGRect(x: 0, y: lh + mh, width: lw, height: rh),  // bottom-left
    CGRect(x: lw, y: lh + mh, width: mw, height: rh),  // bottom edge
    CGRect(x: lw + mw, y: lh + mh, width: rw, height: rh),  // bottom-right
  ]
}

// Returns nil for "skip this rendition" (we only know how to replace ARGB and GA8).
func replace(rendition: CUIThemeRendition, carKey: Data) -> Bool? {
  let pf = rendition.pixelFormat()
  guard pf == kFormatARGB || pf == kFormatGA8 else { return nil }

  let size = rendition.unslicedSize()
  if ProcessInfo.processInfo.environment["CAR_EDIT_INV"] != nil {
    let fmt = pf == kFormatGA8 ? "GA8 " : "ARGB"
    print("inv \(fmt) \(Int(size.width))x\(Int(size.height)) \(rendition.name())")
  }
  let layoutRaw: Int64 = rendition.type() == 0 ? Int64(rendition.subtype()) : rendition.type()
  let layout = Int16(truncatingIfNeeded: layoutRaw)

  // Pull the original slice geometry. WindowShapeEdges renditions are 9-patches;
  // a uniform single-slice replacement (our previous approach) collapsed the
  // edge regions into the corner image and bled across the top of every window.
  // Replicate the original 9 slice rects so the corner caps stay corner-shaped.
  let sliceInfo = rendition.sliceInformation()
  let sliceRects: [CGRect]
  let sliceCount: UInt32
  if let info = sliceInfo {
    let tl = info._topLeftCapSize()
    let br = info._bottomRightCapSize()
    let ei = info.edgeInsets()
    if ProcessInfo.processInfo.environment["CAR_EDIT_DEBUG"] != nil {
      print(
        "rendition \(rendition.name()) size=\(size) tl=\(tl) br=\(br) edgeInsets=t\(ei.top) l\(ei.left) b\(ei.bottom) r\(ei.right) renditionType=\(info.renditionType())"
      )
    }
    if tl != .zero || br != .zero {
      sliceRects = ninePatchSliceRects(canvas: size, tl: tl, br: br)
      sliceCount = 9
    } else {
      sliceRects = [CGRect(origin: .zero, size: size)]
      sliceCount = 1
    }
  } else {
    if ProcessInfo.processInfo.environment["CAR_EDIT_DEBUG"] != nil {
      print("rendition \(rendition.name()) size=\(size) sliceInformation=nil")
    }
    sliceRects = [CGRect(origin: .zero, size: size)]
    sliceCount = 1
  }

  if ProcessInfo.processInfo.environment["CAR_EDIT_DUMP"] != nil {
    dumpAlphaMap(rendition)
  }

  guard
    let bitmap = makeReplacementBitmap(
      width: UInt32(size.width),
      height: UInt32(size.height),
      pixelFormat: pf
    )
  else { return false }

  guard
    let generator = CSIGenerator(
      canvasSize: size,
      sliceCount: sliceCount,
      layout: layout
    )
  else { return false }

  generator.addBitmap(bitmap)
  for rect in sliceRects { generator.addSliceRect(rect) }
  prepareToEdit(generator: generator, fromRendition: rendition)

  guard let newCSI = generator.csiRepresentation(withCompression: true) else { return false }

  return storage.setAsset(newCSI, forKey: carKey)
}

// Copy metadata from an existing rendition into a fresh generator so the
// repacked CSI carries the same encoding/orientation/scale info as the
// source. This is what AssetCatalogWrapper's CSIGenerator.prepareToEdit
// extension does — there's no real Obj-C method by that name.
func prepareToEdit(generator: CSIGenerator, fromRendition r: CUIThemeRendition) {
  generator.name = r.name()
  generator.blendMode = r.blendMode
  generator.colorSpaceID = Int16(truncatingIfNeeded: r.colorSpaceID())
  generator.exifOrientation = r.exifOrientation
  generator.opacity = r.opacity
  generator.scaleFactor = UInt32(r.scale())
  generator.templateRenderingMode = r.templateRenderingMode()
  generator.utiType = r.utiType()
  generator.isVectorBased = r.isVectorBased()
}

// Walk the named-lookup table, follow internal links to the actual storage
// key, dedupe (multiple lookups can alias the same payload), then replace.

var processedCarKeys = Set<Data>()
var matched = 0
var replaced = 0
var failed = 0

catalog.enumerateNamedLookups { lookup in
  guard lookup.name.contains("WindowShapeEdges") else { return }
  matched += 1

  // Use the LOOKUP's own key + rendition. Earlier we resolved internal links
  // to the underlying packed atlas — but that atlas is shared with many other
  // assets, and replacing it stomped over them (the white bar). Writing a
  // self-contained CSI at lookup.key turns this lookup into a non-link entry
  // pointing at our new bytes, while leaving the original atlas untouched.
  let keyList = lookup.key.keyList()
  guard let carKey = themeStore.convertRenditionKey(toKeyData: keyList) else {
    failed += 1
    return
  }
  let carKeyData = carKey as Data
  if processedCarKeys.contains(carKeyData) { return }
  processedCarKeys.insert(carKeyData)

  switch replace(rendition: lookup.rendition, carKey: carKeyData) {
  case .some(true): replaced += 1
  case .some(false): failed += 1
  case .none: break  // intentionally skipped (e.g. unknown pixelFormat)
  }
}

if failed > 0 {
  FileHandle.standardError.write(
    Data("error: \(failed) renditions failed during replace (matched=\(matched))\n".utf8))
  exit(1)
}

if !storage.writeToDisk(compact: true) {
  FileHandle.standardError.write(Data("error: writeToDisk failed\n".utf8))
  exit(1)
}

print("matched \(matched) lookups, replaced \(replaced) unique renditions, wrote \(outputPath)")
