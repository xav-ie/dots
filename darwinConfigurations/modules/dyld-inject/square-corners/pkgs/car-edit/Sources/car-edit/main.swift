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
//   GA8  = the shape-mask anti-aliased edge → we want uniform semi-opaque
//          white at alpha 0.54902, matching ZimengXiong / Shiqi Mei's recipe.
//          A fully-opaque fill (alpha=1.0) bleeds across edges as a white
//          bar; alpha=0.54902 matches the original anti-aliased corner pixel
//          and lets the rectangular AppKit chrome show through cleanly.
let kFormatARGB: Int32 = 0x4152_4742
let kFormatGA8: Int32 = 0x4741_3820

func makeReplacementBitmap(
  width: UInt32, height: UInt32, pixelFormat: Int32
) -> CSIBitmapWrapper? {
  guard let wrapper = CSIBitmapWrapper(pixelWidth: width, pixelHeight: height) else { return nil }
  let ctx = wrapper.bitmapContext().takeUnretainedValue()
  let rect = CGRect(x: 0, y: 0, width: Int(width), height: Int(height))
  if pixelFormat == kFormatGA8 {
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.54902))
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
