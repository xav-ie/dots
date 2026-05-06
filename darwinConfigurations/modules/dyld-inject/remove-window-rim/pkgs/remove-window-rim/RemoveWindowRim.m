// Zero out the rim parameters in -[NSWindow shadowParameters] so
// macOS Tahoe's 1px Liquid-Glass window border never gets pushed to
// WindowServer.
//
// The rim is configured per-window via the dictionary returned by
// `-[NSWindow shadowParameters]`. AppKit reads keys like
// `com.apple.WindowShadowRimRadiusActive`, `WindowShadowRimDensityActive`
// (+ Inactive variants and InnerRim* counterparts) and pushes the
// values to WindowServer via CGS. On Tahoe these default to non-zero
// (Radius=2, Density=0.95). Zeroing them in the returned dict before
// AppKit reads it makes the CGS push paint no rim — and because every
// AppKit process answers from its own swizzled getter, Dock restarts
// (which trigger AppKit to re-push shadow params in long-lived
// processes) don't reintroduce the rim.
//
// Loaded into every launchd-spawned GUI process via the shared
// services.dyldInject.libraries mechanism (see
// darwinConfigurations/modules/dyld-inject/default.nix).
//
// History — what NOT to repeat:
//   • CALayer setRim* setter no-ops (setRimWidth:, setRimOpacity:,
//     setRimColor:, setRimPathIsBounds:): hooks attach successfully but
//     the rim still draws — those CALayer properties are not on the
//     path AppKit uses to push the rim to WindowServer.
//   • A previous attempt to swizzle shadowParameters boot-looped Finder.
//     Root cause: `static NSArray *zeroKeys = @[...];` inside a
//     dispatch_once block is autoreleased (we build without ARC), so
//     the static pointer dangles after the calling thread's autorelease
//     pool drains. Fix is `[@[...] retain]` — see below.
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
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

typedef id (*orig_shadowParameters_t)(id, SEL);
static orig_shadowParameters_t orig_shadowParameters = NULL;

static id swizzled_shadowParameters(id self, SEL _cmd) {
  id ret = orig_shadowParameters ? orig_shadowParameters(self, _cmd) : nil;
  if (![ret isKindOfClass:[NSDictionary class]])
    return ret;

  // Tahoe returns __NSDictionaryM (already mutable). Mutate in place to
  // avoid retain/autorelease ambiguity on the returned object.
  static NSArray *zeroKeys = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    zeroKeys = [@[
      @"com.apple.WindowShadowRimRadiusActive",
      @"com.apple.WindowShadowRimRadiusInactive",
      @"com.apple.WindowShadowRimDensityActive",
      @"com.apple.WindowShadowRimDensityInactive",
      @"com.apple.WindowShadowInnerRimRadiusActive",
      @"com.apple.WindowShadowInnerRimRadiusInactive",
      @"com.apple.WindowShadowInnerRimDensityActive",
      @"com.apple.WindowShadowInnerRimDensityInactive",
    ] retain]; // MUST retain — non-ARC build, otherwise dangles after
               // the calling autorelease pool drains.
  });

  NSMutableDictionary *m = [ret isKindOfClass:[NSMutableDictionary class]]
                               ? (NSMutableDictionary *)ret
                               : [[ret mutableCopy] autorelease];
  for (NSString *k in zeroKeys) {
    if (m[k])
      m[k] = @0;
  }
  return m;
}

__attribute__((constructor)) static void init(void) {
  @autoreleasepool {
    if (![[NSBundle mainBundle] bundleIdentifier])
      return;

    Class win = NSClassFromString(@"NSWindow");
    if (win) {
      SEL sel = @selector(shadowParameters);
      Method m = class_getInstanceMethod(win, sel);
      if (m) {
        orig_shadowParameters =
            (orig_shadowParameters_t)method_getImplementation(m);
        method_setImplementation(m, (IMP)swizzled_shadowParameters);
      }
    }
  }
}
