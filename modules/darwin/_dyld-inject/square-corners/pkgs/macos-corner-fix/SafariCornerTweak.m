// Override NSThemeFrame's corner-rounding methods (the upstream m4rkw
// recipe) so AppKit reports zero radius and Tahoe stops rounding the
// per-window corner mask.
//
// Pairs with the system-wide Aqua.car patch in ../aqua-patcher and
// ../car-edit, which rewrites WindowShapeEdges renditions so
// WindowServer clips windows to a hard rectangle. Without the .car
// patch, AppKit clips windows to a rounded shape regardless of what
// NSThemeFrame reports; without this dylib, AppKit can still draw
// rounded chrome inside the clipped window region.
//
// Window *border* (the 1px Liquid-Glass rim) is handled by a separate
// module — see darwinConfigurations/modules/remove-window-rim/.
//
// History — what NOT to repeat:
//   • Constructor without an @autoreleasepool wrapper crashed
//     fileproviderd (and any non-AppKit daemon launchd injected the
//     dylib into): dyld runs constructors before main, and daemons have
//     no NSApplicationMain to install a thread autorelease pool, so the
//     first autoreleased object inside +[NSBundle mainBundle] trips
//     _objc_fatal ("autorelease pool push without a thread default
//     autorelease pool") → SIGABRT. launchd throttled retries to 20min,
//     which broke NSOpenPanel sidebars (Firefox/Chrome file pickers
//     hung) and the Apple Account settings pane. Fix: wrap the entire
//     constructor in @autoreleasepool.
//
// `___CORNER_RADIUS___` is substituted by our Nix package at build time
// from the `services.dyldInject.squareCorners.cornerRadius` option.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static CGFloat kDesiredCornerRadius = ___CORNER_RADIUS___;

// ---------- NSThemeFrame radius getters ----------

static double swizzled_cornerRadius(id self, SEL _cmd) {
  return kDesiredCornerRadius;
}
static double swizzled_getCachedCornerRadius(id self, SEL _cmd) {
  return kDesiredCornerRadius;
}
static CGSize swizzled_topCornerSize(id self, SEL _cmd) {
  return CGSizeMake(kDesiredCornerRadius, kDesiredCornerRadius);
}
static CGSize swizzled_bottomCornerSize(id self, SEL _cmd) {
  return CGSizeMake(kDesiredCornerRadius, kDesiredCornerRadius);
}

// ---------- install ----------

static void hookIfPresent(Class cls, SEL sel, IMP impl) {
  Method m = class_getInstanceMethod(cls, sel);
  if (m)
    method_setImplementation(m, impl);
}

__attribute__((constructor)) static void init(void) {
  @autoreleasepool {
    if (![[NSBundle mainBundle] bundleIdentifier])
      return;

    Class themeFrame = NSClassFromString(@"NSThemeFrame");
    if (themeFrame) {
      hookIfPresent(themeFrame, @selector(_cornerRadius),
                    (IMP)swizzled_cornerRadius);
      hookIfPresent(themeFrame, @selector(_getCachedWindowCornerRadius),
                    (IMP)swizzled_getCachedCornerRadius);
      hookIfPresent(themeFrame, @selector(_topCornerSize),
                    (IMP)swizzled_topCornerSize);
      hookIfPresent(themeFrame, @selector(_bottomCornerSize),
                    (IMP)swizzled_bottomCornerSize);
    }
  }
}
