// Pin macOS's iPhone Mirroring window (bundle id com.apple.ScreenContinuity)
// to NSFloatingWindowLevel so it sits above normal app windows.
//
// Loaded into every launchd-spawned GUI process via the shared
// services.dyldInject.libraries mechanism (see
// darwinConfigurations/modules/dyld-inject/default.nix), but the
// constructor bails immediately for every other bundle id, so this is
// effectively a no-op everywhere except inside iPhone Mirroring.
//
// Three layers, in install order:
//
//   1. Swizzle -[NSWindow setLevel:] to clamp anything below floating
//      up to floating. Catches any later attempt by Apple's code (or
//      a future macOS update) to drop the level back down.
//
//   2. On NSApplicationDidFinishLaunchingNotification, walk
//      [NSApplication.sharedApplication windows] and bump each window
//      to floating. Necessary because AppKit creates the default
//      main window at NSNormalWindowLevel (= 0) without going through
//      -[NSWindow setLevel:], so the swizzle alone wouldn't fire.
//
//   3. On NSWindowDidBecomeKeyNotification, ensure the key window is
//      at floating. Safety net for windows created after launch (e.g.
//      a re-opened mirroring session, secondary windows).
//
// History — what NOT to repeat:
//   • Constructor without an @autoreleasepool wrapper crashed
//     fileproviderd (and any non-AppKit daemon launchd injected the
//     dylib into): dyld runs constructors before main, and daemons
//     have no NSApplicationMain to install a thread autorelease pool,
//     so the first autoreleased object inside +[NSBundle mainBundle]
//     trips _objc_fatal → SIGABRT. Always wrap the constructor body
//     in @autoreleasepool.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

typedef void (*orig_setLevel_t)(id, SEL, NSInteger);
static orig_setLevel_t orig_setLevel = NULL;

static void swizzled_setLevel(id self, SEL _cmd, NSInteger level) {
  if (level < NSFloatingWindowLevel) {
    level = NSFloatingWindowLevel;
  }
  if (orig_setLevel) {
    orig_setLevel(self, _cmd, level);
  }
}

static void pinAllExistingWindows(void) {
  for (NSWindow *win in [[NSApplication sharedApplication] windows]) {
    if ([win level] < NSFloatingWindowLevel) {
      [win setLevel:NSFloatingWindowLevel];
    }
  }
}

__attribute__((constructor)) static void init(void) {
  @autoreleasepool {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isEqualToString:@"com.apple.ScreenContinuity"]) {
      return;
    }

    Class win = NSClassFromString(@"NSWindow");
    if (win) {
      SEL sel = @selector(setLevel:);
      Method m = class_getInstanceMethod(win, sel);
      if (m) {
        orig_setLevel = (orig_setLevel_t)method_getImplementation(m);
        method_setImplementation(m, (IMP)swizzled_setLevel);
      }
    }

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  pinAllExistingWindows();
                }];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowDidBecomeKeyNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  NSWindow *w = note.object;
                  if ([w level] < NSFloatingWindowLevel) {
                    [w setLevel:NSFloatingWindowLevel];
                  }
                }];
  }
}
