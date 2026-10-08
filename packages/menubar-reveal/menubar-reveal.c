// Run a command with the auto-hidden native menu bar force-revealed but fully
// transparent, so Control Center popovers pressed via AX open immediately
// instead of waiting for the menu bar's slide-down animation.
//
// An open popover is closed with Escape rather than by re-pressing its item:
// with the pointer resting on the bar, a press makes macOS slide the native
// menu bar down over sketchybar. Re-running the same command just closes it.
//
// Most Control Center popovers are instead dismissed by the click's own
// mouse-down, before the click_script gets here. So a detached watcher stamps
// when each popover closes, and the same command arriving right after that is
// the toggle-off and does nothing (rather than reopening it).
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

typedef int (*main_cid_fn)(void);
typedef int (*override_fn)(int cid, int did, bool enabled);
typedef int (*alpha_fn)(int cid, double u1, double u2, float alpha);

// Whether Control Center has an on-screen window taller (popover) or not
// (status item, i.e. the native menu bar is showing) than the menu bar, and
// its frame.
static bool cc_window(bool tall, CGRect *frame) {
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
  if (!windows)
    return false;
  bool open = false;
  for (CFIndex i = 0; i < CFArrayGetCount(windows) && !open; i++) {
    CFDictionaryRef w = CFArrayGetValueAtIndex(windows, i);
    CFStringRef owner = CFDictionaryGetValue(w, kCGWindowOwnerName);
    CFDictionaryRef bounds = CFDictionaryGetValue(w, kCGWindowBounds);
    CGRect rect;
    open = owner &&
           CFStringCompare(owner, CFSTR("Control Center"), 0) ==
               kCFCompareEqualTo &&
           bounds && CGRectMakeWithDictionaryRepresentation(bounds, &rect) &&
           (rect.size.height > 60) == tall;
    if (open && frame)
      *frame = rect;
  }
  CFRelease(windows);
  return open;
}

static bool popover_open(void) { return cc_window(true, NULL); }

// nu click_scripts take ~300ms to get here after the dismissing mouse-down.
// ponytail: fixed window, so clicking away and then on the same item within it
// is still swallowed; a real fix needs the click's own timestamp.
#define TOGGLE_WINDOW_MS 600

static long long now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static FILE *state_file(const char *name, const char *mode) {
  char path[1024];
  const char *tmp = getenv("TMPDIR");
  snprintf(path, sizeof path, "%s/menubar-reveal.%s", tmp ? tmp : "/tmp", name);
  return fopen(path, mode);
}

static int run(char **argv) {
  int status = 1;
  pid_t pid = fork();
  if (pid == 0) {
    execvp(argv[0], argv);
    perror(argv[0]);
    _exit(127);
  }
  if (pid > 0)
    waitpid(pid, &status, 0);
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

// Each stamp is consumed (reset to 0) by the click it accounts for, so only
// the click that dismissed the popover is swallowed, never a quick reopen.
static void stamp_closed(long long ms) {
  FILE *f = state_file("closed", "w");
  if (f) {
    fprintf(f, "%lld", ms);
    fclose(f);
  }
}

static char *escape_cmd[] = {
    "osascript", "-e", "tell application \"System Events\" to key code 53",
    NULL};

// sketchybar's height (nix-settings get_bar_height).
#define BAR_HEIGHT 32

static CGRect popover_frame;
static CFMachPortRef click_tap;
static bool tap_closed;
static CGPoint tap_point;

// A popover's window starts at y=0, so its transparent top strip covers the
// bar items beneath it and Control Center swallows their clicks (sketchybar
// never sees them). Close the popover on such a click; the watcher then replays
// it to sketchybar so it acts as usual (toggle-off on the same item, open on
// another).
static CGEventRef on_mouse_down(CGEventTapProxy proxy, CGEventType type,
                                CGEventRef event, void *ctx) {
  if (type == kCGEventTapDisabledByTimeout ||
      type == kCGEventTapDisabledByUserInput) {
    CGEventTapEnable(click_tap, true);
    return event;
  }
  CGPoint p = CGEventGetLocation(event);
  if (p.y < BAR_HEIGHT && p.x >= CGRectGetMinX(popover_frame) &&
      p.x < CGRectGetMaxX(popover_frame)) {
    tap_closed = true;
    tap_point = p;
    if (fork() == 0) {
      execvp(escape_cmd[0], escape_cmd);
      _exit(127);
    }
  }
  return event;
}

// Watcher mode, run as a fresh exec (CoreGraphics isn't fork-safe): wait for
// the popover to appear, close it on swallowed bar clicks while it's open,
// then stamp the close time. The listen-only tap rides on the Accessibility
// trust sketchybar's launch chain already has (as do the osascript presses).
static int watch_close(void) {
  for (int i = 0; i < 100 && !cc_window(true, &popover_frame); i++)
    usleep(10000);
  click_tap = CGEventTapCreate(
      kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
      CGEventMaskBit(kCGEventLeftMouseDown), on_mouse_down, NULL);
  if (click_tap)
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       CFMachPortCreateRunLoopSource(NULL, click_tap, 0),
                       kCFRunLoopCommonModes);
  while (popover_open()) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    while (waitpid(-1, NULL, WNOHANG) > 0)
      ;
  }
  stamp_closed(now_ms());
  if (tap_closed) {
    CGEventType types[] = {kCGEventLeftMouseDown, kCGEventLeftMouseUp};
    for (int i = 0; i < 2; i++) {
      CGEventRef e = CGEventCreateMouseEvent(NULL, types[i], tap_point,
                                             kCGMouseButtonLeft);
      CGEventPost(kCGHIDEventTap, e);
      CFRelease(e);
    }
  }
  return 0;
}

static bool closed_just_now(void) {
  long long closed = 0;
  FILE *f = state_file("closed", "r");
  if (f) {
    fscanf(f, "%lld", &closed);
    fclose(f);
  }
  return now_ms() - closed < TOGGLE_WINDOW_MS;
}

// Records argv as the last command run, returning whether it matches the
// previous one (i.e. the same menu bar item is being clicked again).
// ponytail: last-command file, so a popover opened natively (not through this)
// gets switched to, not closed, on the first click here.
static bool same_as_last(int argc, char **argv) {
  char prev[4096] = "", cur[4096] = "";
  for (int i = 1; i < argc; i++) {
    strlcat(cur, argv[i], sizeof cur);
    strlcat(cur, "\x1f", sizeof cur);
  }
  FILE *f = state_file("last", "r");
  if (f) {
    prev[fread(prev, 1, sizeof prev - 1, f)] = 0;
    fclose(f);
  }
  if ((f = state_file("last", "w"))) {
    fputs(cur, f);
    fclose(f);
  }
  return strcmp(prev, cur) == 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <command> [args...]\n", argv[0]);
    return 2;
  }
  if (strcmp(argv[1], "--watch-close") == 0)
    return watch_close();
  bool same = same_as_last(argc, argv);
  if (same && !popover_open() && closed_just_now()) {
    stamp_closed(0);
    return 0;
  }
  if (popover_open()) {
    int status = run(escape_cmd);
    if (same) {
      // Let the watcher stamp this close (it polls every 20ms), then consume
      // it.
      for (int i = 0; i < 50 && popover_open(); i++)
        usleep(10000);
      usleep(60000);
      stamp_closed(0);
      return status;
    }
    // Switching items: pressing another while one is open wedges Control
    // Center, so open the new one only once the old one is gone.
    for (int i = 0; i < 50 && popover_open(); i++)
      usleep(10000);
  }

  void *sl =
      dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
             RTLD_LAZY);
  main_cid_fn main_cid =
      sl ? (main_cid_fn)dlsym(sl, "SLSMainConnectionID") : NULL;
  override_fn set_override =
      sl ? (override_fn)dlsym(sl, "SLSSetMenuBarVisibilityOverrideOnDisplay")
         : NULL;
  alpha_fn set_alpha =
      sl ? (alpha_fn)dlsym(sl, "SLSSetMenuBarInsetAndAlpha") : NULL;
  bool ok = main_cid && set_override && set_alpha;
  int cid = ok ? main_cid() : 0;

  if (ok) {
    set_alpha(cid, 0, 1, 0.0);
    set_override(cid, 0, true);
    set_alpha(cid, 0, 1, 0.0);
  }
  int status = run(argv + 1);
  if (ok) {
    set_override(cid, 0, false);
    // Stay transparent until the native menu bar has slid back up, or the
    // tail of that animation flashes over sketchybar.
    for (int i = 0; i < 100 && cc_window(false, NULL); i++)
      usleep(10000);
    set_alpha(cid, 0, 1, 1.0);
  }
  if (fork() == 0) {
    setsid();
    execlp(argv[0], argv[0], "--watch-close", (char *)NULL);
    _exit(127);
  }
  return status;
}
