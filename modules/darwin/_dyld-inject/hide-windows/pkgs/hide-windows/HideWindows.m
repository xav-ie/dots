// hide-windows: exclude every GUI app's windows from screen capture (the
// macOS answer to Invisiwind), toggleable per-process on demand.
//
// Mechanism: an app's window is excluded from window-level capture
// (ScreenCaptureKit, CGWindowListCreateImage, and all browser
// getDisplayMedia sharing — incl. Zoom-in-a-tab) when its
// NSWindow.sharingType is NSWindowSharingNone. That flag ONLY takes
// effect when set by the process that owns the window — a cross-process
// CGSSetWindowSharingState returns success but silently no-ops
// (verified). So we ride the shared services.dyldInject.libraries inject
// to run INSIDE every GUI process and flip the flag from the inside.
//
// Ceiling: window-level capture only. The native Zoom desktop app's
// default mode reads the raw display buffer BELOW the window layer and
// bypasses this (share via a browser tab and it's honored). Apple marks
// sharingType legacy as of Sequoia.
//
// State model: windows are VISIBLE by default (normal mode) — so
// continuous screen recorders like Dayflow keep working. The hidewin
// menubar's "Screenshare Mode" (or `hidewin hide --all`) posts a HIDE
// notification that flips every app to excluded-from-capture for the
// duration of a meeting; `hidewin show <target>|--all` reveals again.
// A window can't be hidden from one capturer but shown to another — the
// sharing flag is per-window, honored by all window-level capturers — so
// hiding during a meeting hides from Dayflow too, by necessity.
//
// Targeting: a notification's object matches this process if it equals
// our PID (per-instance — lets you reveal ONE of two Firefox profile
// instances that share a bundle id), OR our bundle id (all instances of
// an app — what the CLI uses), OR is nil (every app). We also announce a
// human label (PID + a friendly name derived from our window title, which
// carries e.g. Firefox's "— Work" profile suffix) so the menubar can tell
// same-bundle instances apart — read in-process, so no capture permission.
//
// History — what NOT to repeat (from sibling dylibs, same inject path):
//   • Constructor MUST be wrapped in @autoreleasepool: dyld runs it
//     before main, and non-AppKit daemons launchd injects us into have
//     no thread autorelease pool, so the first autoreleased object
//     trips _objc_fatal → SIGABRT (launchd then throttles retries 20min
//     and breaks file pickers). Bail on nil bundleIdentifier too.
//   • Non-ARC build: retain any static object or it dangles after the
//     calling autorelease pool drains.
//   • setSharingType: is a WindowServer round-trip and orderWindow: is
//     hot — write only when the value actually changes (applyWindow),
//     else the whole desktop lags.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static int g_hidden = 0;           // default: VISIBLE (normal mode); menubar
                                   // Screenshare Mode flips this to hidden
static NSString *g_bundleID = nil; // this process's bundle id (retained)
static NSString *g_pid = nil;      // this process's pid as a string (retained)
// Window numbers explicitly revealed while hidden — the menubar reveals per
// WINDOW, not just per process, so you can present one document and keep the
// rest of the same app excluded. Empty means "the whole process follows
// g_hidden". Cleared by any process-wide show/hide, since that restates intent.
static NSMutableSet *g_revealed = nil;

static NSInteger sharingFor(NSWindow *w) {
  // ReadOnly (not ReadWrite) is the normal capturable state; either
  // non-zero value restores visibility.
  BOOL hide = g_hidden && ![g_revealed containsObject:@([w windowNumber])];
  return hide ? NSWindowSharingNone : NSWindowSharingReadOnly;
}

static void applyWindow(NSWindow *w) {
  if ([w sharingType] != sharingFor(w))
    [w setSharingType:sharingFor(w)];
}

// The one and only safe way to reach the app's windows. Two rules:
//   • NEVER call [NSApplication sharedApplication] — it INSTANTIATES NSApp
//     with the default .regular policy. In a background daemon (which
//     never created one) that promotes the daemon into the ⌘-Tab switcher
//     and Dock. Read the NSApp global instead: nil until the app itself
//     makes one.
//   • Only act on real foreground apps (.regular). Accessory/menubar
//     helpers and prohibited daemons have nothing worth hiding and must
//     not be perturbed.
static NSApplication *regularApp(void) {
  NSApplication *app = NSApp; // does NOT instantiate
  if (app && app.activationPolicy == NSApplicationActivationPolicyRegular)
    return app;
  return nil;
}

static void applyAll(void) {
  NSApplication *app = regularApp();
  if (!app)
    return;
  for (NSWindow *w in [app windows])
    applyWindow(w);
}

// A show/hide notification targets us if its object is nil (broadcast),
// our pid (this instance), or our bundle id (every instance of the app).
static BOOL targetsUs(NSString *o) {
  return !o || [o isEqualToString:g_pid] || [o isEqualToString:g_bundleID];
}

// An object may carry a window suffix: "<target>#<windowNumber>" addresses one
// window of that target, plain "<target>" the whole process. Returns the window
// number via *win (nil for process-wide) and the target via *who.
static void splitTarget(NSString *o, NSString **who, NSNumber **win) {
  *who = o;
  *win = nil;
  if (!o)
    return;
  NSRange r = [o rangeOfString:@"#" options:NSBackwardsSearch];
  if (r.location == NSNotFound)
    return;
  *who = [o substringToIndex:r.location];
  *win = @([[o substringFromIndex:r.location + 1] integerValue]);
}

// Apply a show (reveal = YES) or hide to whatever the object addressed.
static void applyRequest(NSString *object, BOOL reveal) {
  NSString *who = nil;
  NSNumber *win = nil;
  splitTarget(object, &who, &win);
  if (!targetsUs(who))
    return;
  if (win) {
    if (reveal)
      [g_revealed addObject:win];
    else
      [g_revealed removeObject:win];
  } else {
    g_hidden = reveal ? 0 : 1;
    [g_revealed removeAllObjects];
  }
  applyAll();
}

// Friendly label for the menubar: app name plus the profile-ish suffix
// after the last " — " in a window title (Firefox appends "— Work" etc.).
static NSString *friendlyLabel(void) {
  NSString *name =
      [[NSRunningApplication currentApplication] localizedName] ?: g_bundleID;
  NSString *title = nil;
  for (NSWindow *w in [NSApp windows]) { // NSApp global, never instantiate
    if (w.title.length) {
      title = w.title;
      break;
    }
  }
  NSRange r = [title rangeOfString:@" — " options:NSBackwardsSearch];
  if (title && r.location != NSNotFound) {
    NSString *suffix = [title substringFromIndex:r.location + [@" — " length]];
    if (suffix.length)
      return [NSString stringWithFormat:@"%@ — %@", name, suffix];
  }
  return name;
}

static void announceWindows(void);

// Tell the menubar who we are: object = "<pid>\t<label>". Only real
// foreground apps announce — daemons/accessory helpers stay out of the
// menu (and, crucially, we never touch NSApp in them).
static void announce(void) {
  if (!regularApp())
    return;
  NSString *obj = [NSString stringWithFormat:@"%@\t%@", g_pid, friendlyLabel()];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:@"com.x.hidewin.iam"
                    object:obj
                  userInfo:nil
        deliverImmediately:YES];
  announceWindows();
}

// Is this a window a person would pick out of a menu? NOT "is it titled" —
// Ghostty (macos-titlebar-style = hidden) draws real terminal windows with no
// title bar at all, and they're exactly what you want to reveal one of.
// canBecomeMainWindow is the honest test: it's what AppKit itself uses to mean
// "a primary window", so palettes, HUDs, and hidden helper windows (Ghostty's
// TUINSWindow, an offscreen "Configuration Errors" alert) fall out for free.
static BOOL listableWindow(NSWindow *w) {
  return w.isVisible && [w canBecomeMainWindow] && w.frame.size.width >= 200 &&
         w.frame.size.height >= 100;
}

// The best human label available. A title is preferred, but plenty of windows
// have a useless one — a terminal configured with `title = " "` reports a
// single space — so fall back to the tab title, then to the represented file
// (Ghostty points this at the working directory, which is what you'd actually
// recognise). Empty is a fine answer; the menubar numbers those.
static NSString *windowLabel(NSWindow *w) {
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  for (NSString *candidate in @[ w.title ?: @"", w.tab.title ?: @"" ]) {
    NSString *t = [candidate stringByTrimmingCharactersInSet:ws];
    if (t.length)
      return [t stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
  }
  NSString *path = [[w representedURL] path];
  if (path.length)
    return [path stringByAbbreviatingWithTildeInPath];
  return @"";
}

// Per-window announcement: "<pid>\t<windowNumber>\t<label>", one per window, so
// the menubar can list an app's windows and reveal them individually. Window
// numbers are stable for the life of a window, which is what makes them usable
// as the reveal key.
static void announceWindows(void) {
  NSApplication *app = regularApp();
  if (!app)
    return;
  NSDistributedNotificationCenter *dc =
      [NSDistributedNotificationCenter defaultCenter];
  for (NSWindow *w in [app windows]) {
    if (!listableWindow(w))
      continue;
    [dc postNotificationName:@"com.x.hidewin.iam-window"
                      object:[NSString stringWithFormat:@"%@\t%ld\t%@", g_pid,
                                                        (long)[w windowNumber],
                                                        windowLabel(w)]
                    userInfo:nil
          deliverImmediately:YES];
  }
}

// orderWindow:relativeTo: is the funnel every on-screen ordering routes
// through (orderFront:/makeKeyAndOrderFront: included), so flipping the
// flag here catches every window the instant it's displayed.
typedef void (*orig_orderWindow_t)(id, SEL, NSInteger, NSInteger);
static orig_orderWindow_t orig_orderWindow = NULL;

static void swizzled_orderWindow(id self, SEL _cmd, NSInteger place,
                                 NSInteger relativeTo) {
  applyWindow((NSWindow *)self);
  if (orig_orderWindow)
    orig_orderWindow(self, _cmd, place, relativeTo);
}

__attribute__((constructor)) static void init(void) {
  @autoreleasepool {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID)
      return; // non-app process (daemon/CLI); nothing to hide.
    // Our own menubar manages its own window hiding (a custom sharingType
    // .none panel — native NSMenus ignore the flag). Skip it so this
    // swizzle can't fight/override that.
    if ([bundleID isEqualToString:@"com.x.hidewin-bar"])
      return;
    g_bundleID = [bundleID retain];
    g_pid = [[NSString stringWithFormat:@"%d", getpid()] retain];
    g_revealed = [[NSMutableSet alloc] init]; // non-ARC: owned deliberately

    // Seed from the current mode so an app launched mid-meeting starts HIDDEN
    // with no gap, instead of flashing visible until the menubar's per-launch
    // HIDE arrives. (Sandboxed apps can't read ~/.cache — they fall back to the
    // notification; the didLaunch HIDE remains a belt-and-suspenders
    // re-assert.)
    NSString *mode =
        [NSString stringWithContentsOfFile:[@"~/.cache/hidewin/mode"
                                               stringByExpandingTildeInPath]
                                  encoding:NSUTF8StringEncoding
                                     error:NULL];
    if ([mode hasPrefix:@"on"])
      g_hidden = 1;

    Class win = NSClassFromString(@"NSWindow");
    if (win) {
      SEL sel = @selector(orderWindow:relativeTo:);
      Method m = class_getInstanceMethod(win, sel);
      if (m) {
        orig_orderWindow = (orig_orderWindow_t)method_getImplementation(m);
        method_setImplementation(m, (IMP)swizzled_orderWindow);
      }
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    // Catch windows created before our run loop spins, and announce once
    // a window (and its title) exists.
    [nc addObserverForName:NSApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  applyAll();
                  announce();
                }];
    // Re-announce when a window becomes key — its title (and thus the
    // profile suffix) is reliably set by then.
    [nc addObserverForName:NSWindowDidBecomeKeyNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  announce();
                }];

    NSDistributedNotificationCenter *dc =
        [NSDistributedNotificationCenter defaultCenter];
    // Toggle: object is our pid, our bundle id, or nil (all).
    [dc addObserverForName:@"com.x.hidewin.show"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  applyRequest(note.object, YES);
                }];
    [dc addObserverForName:@"com.x.hidewin.hide"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  applyRequest(note.object, NO);
                }];
    // The menubar asks "who's out there?" on launch / menu open; reply.
    [dc addObserverForName:@"com.x.hidewin.who"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  announce();
                }];
  }
}
