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

// Quick Look's panel (Finder's spacebar preview) is its own window, so a
// per-window reveal never covers it. It stands in for the window it previews
// from — the app's main window (a panel never becomes main itself) — so a
// preview opened from a revealed window is shown, and one opened from a hidden
// window stays hidden.
static NSWindow *revealProxy(NSWindow *w) {
  static Class ql = Nil; // QuickLookUI loads lazily; resolve once it exists
  if (!ql)
    ql = NSClassFromString(@"QLPreviewPanel");
  if (ql && [w isKindOfClass:ql] && [NSApp mainWindow])
    return [NSApp mainWindow];
  return w;
}

static NSInteger sharingFor(NSWindow *w) {
  // ReadOnly (not ReadWrite) is the normal capturable state; either
  // non-zero value restores visibility.
  BOOL hide = g_hidden && ![g_revealed
                              containsObject:@([revealProxy(w) windowNumber])];
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

// ── Dock ──────────────────────────────────────────────────────────────────
// Dock draws Mission Control's hover outline + window title and the Dock icon
// name tooltips in its own windows, which ignore sharingType (setting it
// sticks, but capture still sees them — verified). So Dock never draws them:
//   • plain CALayer with a ≥4pt border — Mission Control's hover outline (5pt;
//     the 3pt one is the Spaces bar's selection, left alone), added at the
//     hovered window's rect and removed on unhover.
//   • ECTooltipLayer — Mission Control's window title (one reused layer,
//     retitled just before each outline appears, drawn centred on it).
//   • DOCKLabelLayer — the name over a hovered Dock icon (text from its Tile).
// Instead we report what Dock wanted to show to hidewin-bar's DockOverlay
// (com.x.hidewin.dock-ui; protocol in packages/hidewin-bar/DockOverlay.swift),
// which draws look-alikes in sharingType = .none panels: visible to you, never
// captured. Mission Control's window thumbnails need nothing: they're the real
// windows, already hidden from capture in Screenshare Mode.
static NSHashTable *g_outlines = nil; // outline layers seen (weak)
static NSString *g_title = @"";       // Mission Control's current window title
static NSMutableDictionary *g_dockPending = nil, *g_dockSent = nil;
static char kWantHidden;
static IMP o_tooltipLayout, o_tooltipSetHidden, o_labelUpdate, o_labelSetHidden,
    o_setBorderWidth, o_setPosition, o_setBounds, o_removeFromSuperlayer;

// Coalesced: Dock sets an outline's position then bounds, and animates a label
// every frame — post at most once per kind per runloop turn, and only changes.
static void dockPublish(NSString *kind, NSString *message) {
  if (![NSThread isMainThread]) {
    NSString *k = [kind copy], *m = [message copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      dockPublish(k, m);
      [k release];
      [m release];
    });
    return;
  }
  BOOL scheduled = g_dockPending.count > 0;
  g_dockPending[kind] = message;
  if (scheduled)
    return;
  dispatch_async(dispatch_get_main_queue(), ^{
    @autoreleasepool {
      for (NSString *k in g_dockPending) {
        NSString *m = g_dockPending[k];
        if ([m isEqualToString:g_dockSent[k]])
          continue;
        g_dockSent[k] = m;
        [[NSDistributedNotificationCenter defaultCenter]
            postNotificationName:@"com.x.hidewin.dock-ui"
                          object:m
                        userInfo:nil
              deliverImmediately:YES];
      }
      [g_dockPending removeAllObjects];
    }
  });
}

// Dock's overlay windows cover a whole display with a bottom-left origin; map
// a layer to global top-left points on the display under the cursor (where
// any hover UI is).
static NSString *dockRect(CALayer *l) {
  CALayer *root = l;
  while (root.superlayer)
    root = root.superlayer;
  CGRect r = [l convertRect:l.bounds toLayer:root];
  CGEventRef e = CGEventCreate(NULL);
  CGPoint cursor = CGEventGetLocation(e);
  CFRelease(e);
  CGDirectDisplayID display = CGMainDisplayID();
  uint32_t n = 0;
  CGGetDisplaysWithPoint(cursor, 1, &display, &n);
  CGRect d = CGDisplayBounds(display);
  return [NSString stringWithFormat:@"%.1f\t%.1f\t%.1f\t%.1f",
                                    d.origin.x + r.origin.x,
                                    d.origin.y + d.size.height - r.origin.y -
                                        r.size.height,
                                    r.size.width, r.size.height];
}

static BOOL isOutline(CALayer *l) { return [g_outlines containsObject:l]; }

static void publishOutline(CALayer *l) {
  if (l.superlayer && l.bounds.size.width > 0)
    dockPublish(@"outline", [NSString stringWithFormat:@"outline\t%@\t%@",
                                                       dockRect(l), g_title]);
}

// Hidden on Dock's screen, always; setHidden: is overridden on the class.
#define DOCK_FORCE_HIDDEN(l, setHidden)                                         \
  ((void (*)(id, SEL, BOOL))setHidden)(l, @selector(setHidden:), YES)

static void tooltipSetHidden(id self, SEL _cmd, BOOL hidden) {
  DOCK_FORCE_HIDDEN(self, o_tooltipSetHidden);
}

static void tooltipLayout(id self, SEL _cmd) {
  ((void (*)(id, SEL))o_tooltipLayout)(self, _cmd);
  DOCK_FORCE_HIDDEN(self, o_tooltipSetHidden);
  id text = [self respondsToSelector:@selector(textLayer)]
                ? [[self performSelector:@selector(textLayer)] string]
                : nil;
  NSString *title = [[text description]
      stringByReplacingOccurrencesOfString:@"\t"
                                withString:@" "];
  if (title && ![title isEqualToString:g_title]) {
    [g_title release];
    g_title = [title copy];
    for (CALayer *l in g_outlines) // retitle an outline already showing
      publishOutline(l);
  }
}

// A label is showing while Dock wants it unhidden and fully faded in; any
// fade-out counts as gone (the overlay hides at once).
static void publishLabel(CALayer *l) {
  BOOL wantHidden = [objc_getAssociatedObject(l, &kWantHidden) boolValue];
  if (wantHidden || l.opacity < 0.99) {
    dockPublish(@"label", @"label\thide");
    return;
  }
  id tile = [l respondsToSelector:@selector(source)]
                ? [l performSelector:@selector(source)]
                : nil;
  NSString *text = [tile respondsToSelector:@selector(label)]
                       ? [tile performSelector:@selector(label)]
                       : nil;
  if (text.length && l.bounds.size.width > 0)
    dockPublish(@"label", [NSString stringWithFormat:@"label\t%@\t%@",
                                                     dockRect(l), text]);
}

static void labelSetHidden(id self, SEL _cmd, BOOL hidden) {
  objc_setAssociatedObject(self, &kWantHidden, @(hidden),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  DOCK_FORCE_HIDDEN(self, o_labelSetHidden);
  publishLabel(self);
}

static void labelUpdate(id self, SEL _cmd) {
  ((void (*)(id, SEL))o_labelUpdate)(self, _cmd);
  DOCK_FORCE_HIDDEN(self, o_labelSetHidden);
  publishLabel(self);
}

static void dockSetBorderWidth(CALayer *self, SEL _cmd, CGFloat width) {
  if (width >= 4 && object_getClass(self) == [CALayer class]) {
    [g_outlines addObject:self];
    width = 0;
  }
  ((void (*)(id, SEL, CGFloat))o_setBorderWidth)(self, _cmd, width);
}

static void dockSetPosition(CALayer *self, SEL _cmd, CGPoint p) {
  ((void (*)(id, SEL, CGPoint))o_setPosition)(self, _cmd, p);
  if (isOutline(self))
    publishOutline(self);
}

static void dockSetBounds(CALayer *self, SEL _cmd, CGRect b) {
  ((void (*)(id, SEL, CGRect))o_setBounds)(self, _cmd, b);
  if (isOutline(self))
    publishOutline(self);
}

static void dockRemoveFromSuperlayer(CALayer *self, SEL _cmd) {
  if (isOutline(self) && self.superlayer)
    dockPublish(@"outline", @"outline\thide");
  ((void (*)(id, SEL))o_removeFromSuperlayer)(self, _cmd);
}

// Override setHidden: on the class itself (it inherits CALayer's), and wrap
// the method Dock calls each time it shows the element.
static void dockHookLabel(const char *cls, SEL show, IMP setHiddenHook,
                          IMP showHook, IMP *origSetHidden, IMP *origShow) {
  Class c = objc_getClass(cls);
  Method m = c ? class_getInstanceMethod(c, show) : NULL;
  if (!m)
    return; // a macOS update renamed it; leave Dock alone
  *origSetHidden = class_getMethodImplementation(c, @selector(setHidden:));
  class_replaceMethod(c, @selector(setHidden:), setHiddenHook, "v@:B");
  *origShow = method_setImplementation(m, showHook);
}

static IMP dockSwizzle(SEL sel, IMP hook) {
  return method_setImplementation(
      class_getInstanceMethod([CALayer class], sel), hook);
}

static void dockInstall(void) {
  g_outlines = [[NSHashTable weakObjectsHashTable] retain];
  g_dockPending = [[NSMutableDictionary alloc] init];
  g_dockSent = [[NSMutableDictionary alloc] init];
  dockHookLabel("ECTooltipLayer", @selector(layout), (IMP)tooltipSetHidden,
                (IMP)tooltipLayout, &o_tooltipSetHidden, &o_tooltipLayout);
  dockHookLabel("DOCKLabelLayer", sel_registerName("update"),
                (IMP)labelSetHidden, (IMP)labelUpdate, &o_labelSetHidden,
                &o_labelUpdate);
  o_setBorderWidth =
      dockSwizzle(@selector(setBorderWidth:), (IMP)dockSetBorderWidth);
  o_setPosition = dockSwizzle(@selector(setPosition:), (IMP)dockSetPosition);
  o_setBounds = dockSwizzle(@selector(setBounds:), (IMP)dockSetBounds);
  o_removeFromSuperlayer = dockSwizzle(@selector(removeFromSuperlayer),
                                       (IMP)dockRemoveFromSuperlayer);
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

    if ([bundleID isEqualToString:@"com.apple.dock"])
      dockInstall();

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
    // An open Quick Look panel follows the main window; re-evaluate when
    // that changes (e.g. clicking into another Finder window mid-preview).
    [nc addObserverForName:NSWindowDidBecomeMainNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  applyAll();
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
