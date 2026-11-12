// Run a command with the auto-hidden native menu bar force-revealed but fully
// transparent, so Control Center popovers pressed via AX open immediately
// instead of waiting for the menu bar's slide-down animation.
//
// An open popover is closed with Escape rather than by re-pressing its item:
// with the pointer resting on the bar, a press makes macOS slide the native
// menu bar down over sketchybar. Re-running the same command just closes it.
//
// Most Control Center popovers are instead dismissed by the click's own
// mouse-down, before the click_script gets here. So this process stays alive
// while its popover is open and stamps when it closes, and the same command
// arriving right after that is the toggle-off and does nothing (rather than
// reopening it).
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <notify.h>
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

// Whether `owner` has an on-screen window that is taller than the menu bar
// (`tall`) or not, optionally also at window level `layer` (-1 for any), and
// its frame.
static bool find_window(CFStringRef owner_name, int layer, bool tall,
                        CGRect *frame) {
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
  if (!windows)
    return false;
  bool found = false;
  for (CFIndex i = 0; i < CFArrayGetCount(windows) && !found; i++) {
    CFDictionaryRef w = CFArrayGetValueAtIndex(windows, i);
    CFStringRef owner = CFDictionaryGetValue(w, kCGWindowOwnerName);
    CFDictionaryRef bounds = CFDictionaryGetValue(w, kCGWindowBounds);
    CFNumberRef level = CFDictionaryGetValue(w, kCGWindowLayer);
    int l = 0;
    CGRect rect;
    found = owner &&
            CFStringCompare(owner, owner_name, 0) == kCFCompareEqualTo &&
            (layer < 0 ||
             (level && CFNumberGetValue(level, kCFNumberIntType, &l) &&
              l == layer)) &&
            bounds && CGRectMakeWithDictionaryRepresentation(bounds, &rect) &&
            (rect.size.height > 60) == tall;
    if (found && frame)
      *frame = rect;
  }
  CFRelease(windows);
  return found;
}

// Control Center still owns the popovers.
static bool popover_open(void) {
  return find_window(CFSTR("Control Center"), -1, true, NULL);
}

// The native menu bar is on screen (revealed, or still sliding). Since macOS 27
// it is a WindowServer-owned window at the main menu level; the status items
// moved to MenuBarAgent.
static bool menubar_showing(void) {
  return find_window(CFSTR("Window Server"),
                     CGWindowLevelForKey(kCGMainMenuWindowLevelKey), false,
                     NULL);
}

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

static alpha_fn set_alpha;
static int cid;

// While the native bar is held revealed-but-transparent over sketchybar, its
// invisible menus and status items sit where sketchybar's items are. Publish
// our pid under this notify key for that time, so sketchybar-hoverd takes the
// bar's clicks; it checks the pid is alive, so a crash can't leave it stuck.
#define HOLD_KEY "com.x.menubar-reveal.holding"

static void publish_hold(bool holding) {
  static int token = -1;
  if (token == -1 && notify_register_check(HOLD_KEY, &token) != NOTIFY_STATUS_OK)
    return;
  uint64_t state = 0;
  // A later click's process may have taken over; only clear our own.
  if (!holding && (notify_get_state(token, &state) != NOTIFY_STATUS_OK ||
                   state != (uint64_t)getpid()))
    return;
  notify_set_state(token, holding ? (uint64_t)getpid() : 0);
  notify_post(HOLD_KEY);
}

// The pointer is where macOS keeps a revealed menu bar revealed: on the bar or
// just below it.
#define REVEALED_REACH 80

static bool pointer_on_bar(void) {
  CGEventRef e = CGEventCreate(NULL);
  if (!e)
    return false;
  CGPoint p = CGEventGetLocation(e);
  CFRelease(e);
  return p.y < REVEALED_REACH;
}

// sketchybar-hoverd swallows bar clicks while we hold the native bar (see
// HOLD_KEY) and announces each one: close the popover, as a click elsewhere
// would.
static void on_bar_clicked(CFNotificationCenterRef center, void *observer,
                           CFNotificationName name, const void *object,
                           CFDictionaryRef info) {
  if (popover_open() && fork() == 0) {
    execvp(escape_cmd[0], escape_cmd);
    _exit(127);
  }
}

// Keep the native menu bar transparent. The alpha is global but reset to
// opaque whenever any process that set it exits, so it is re-asserted on every
// tick rather than set once.
static void hold_transparent(void) {
  if (set_alpha)
    set_alpha(cid, 0, 1, 0.0);
}

// Stay alive while any popover is open (including one a later click switched
// to), keeping the bar transparent: a popover keeps the native menu bar
// revealed for as long as it is open. Closes the popover when sketchybar-hoverd
// announces a bar click and stamps the close time; then waits for the bar to
// slide back up, which it only does once the pointer leaves the bar (it is
// often still there, after a click on another item closed the popover).
static void hold_while_open(void) {
  for (int i = 0; i < 100 && !popover_open(); i++) {
    hold_transparent();
    usleep(10000);
  }
  CFNotificationCenterAddObserver(
      CFNotificationCenterGetDistributedCenter(), NULL, on_bar_clicked,
      CFSTR("bar-panels.bar-clicked"), NULL,
      CFNotificationSuspensionBehaviorDeliverImmediately);
  bool stamped = false;
  long long settle_until = 0;
  for (;;) {
    hold_transparent();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    while (waitpid(-1, NULL, WNOHANG) > 0)
      ;
    if (popover_open()) {
      settle_until = 0;
      continue;
    }
    if (!stamped) {
      stamp_closed(now_ms());
      stamped = true;
    }
    if (!settle_until || pointer_on_bar())
      settle_until = now_ms() + 1000;
    // Stay transparent until the native menu bar has slid back up, or the
    // tail of that animation flashes over sketchybar.
    if (!menubar_showing() || now_ms() > settle_until)
      break;
  }
  publish_hold(false);
  if (set_alpha)
    set_alpha(cid, 0, 1, 1.0);
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
  bool same = same_as_last(argc, argv);
  if (same && !popover_open() && closed_just_now()) {
    stamp_closed(0);
    return 0;
  }
  if (popover_open()) {
    int status = run(escape_cmd);
    if (same) {
      // Let the process holding the popover stamp this close (it polls every
      // 20ms), then consume it.
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
  alpha_fn alpha = sl ? (alpha_fn)dlsym(sl, "SLSSetMenuBarInsetAndAlpha") : NULL;
  bool ok = main_cid && set_override && alpha;
  if (ok) {
    cid = main_cid();
    set_alpha = alpha;
    publish_hold(true);
    hold_transparent();
    set_override(cid, 0, true);
    hold_transparent();
  }
  int status = run(argv + 1);
  if (ok)
    set_override(cid, 0, false);
  hold_while_open();
  return status;
}
