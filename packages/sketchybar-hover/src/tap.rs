//! Global mouse tap that drives hover and clicks while sketchybar is covered.
//!
//! Since macOS 27, MenuBarAgent keeps an invisible, full-width window above
//! the menu bar level while the auto-hidden menu bar is hidden; it is the
//! reveal hot region and swallows every mouse event over sketchybar. A
//! CGEventTap sees those events anyway, so this module hit-tests them against
//! sketchybar's item geometry and replays them: hover as ENTER/EXIT_ALL into
//! the daemon's state machine, left clicks as the item's `click_script` and/or
//! its `mouse.clicked` subscription. It only acts while that window is on
//! screen, i.e. while sketchybar is not receiving the events itself and the
//! native menu bar is not revealed over it.
//!
//! A click on that window reveals the native menu bar, so presses on an item
//! are also swallowed before MenuBarAgent sees them.
//!
//! While menubar-reveal holds the native menu bar revealed but transparent over
//! sketchybar (a Control Center popover is open, or the bar is still sliding
//! away after one), a bar click would land on its invisible menus and status
//! items (the battery's opening the native Battery menu). It publishes its pid
//! for that time, and then every press in the bar is swallowed: items get their
//! click replayed, and each such click is announced so menubar-reveal closes
//! its popover, as a click elsewhere would. That needs an active tap,
//! which needs Accessibility trust: the daemon gets it by being started from
//! sketchybarrc (sketchybar is trusted). Without it the tap falls back to
//! listen-only and clicks still work, but reveal the native menu bar.

use std::ffi::{c_char, c_void, CStr};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicPtr, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use sketchybar_hover::HoverEvent;

const OVERLAY_OWNER: &str = "MenuBarAgent";
const OVERLAY_LAYER: i32 = 25;
/// menubar-reveal's pid while it holds the native bar transparent, else 0.
const HOLD_KEY: &CStr = c"com.x.menubar-reveal.holding";
/// sketchybar's `update_mask` bit for the `mouse.clicked` event.
const MOUSE_CLICKED_BIT: u64 = 1 << 6;
const GEOMETRY_MAX_AGE: Duration = Duration::from_secs(2);
const CLICK_GEOMETRY_MAX_AGE: Duration = Duration::from_millis(500);
const COVER_MAX_AGE: Duration = Duration::from_millis(150);

const K_CG_SESSION_EVENT_TAP: u32 = 1;
const K_CG_HEAD_INSERT_EVENT_TAP: u32 = 0;
const K_CG_EVENT_TAP_OPTION_DEFAULT: u32 = 0;
const K_CG_EVENT_TAP_OPTION_LISTEN_ONLY: u32 = 1;
const K_CG_EVENT_LEFT_MOUSE_DOWN: u32 = 1;
const K_CG_EVENT_LEFT_MOUSE_UP: u32 = 2;
const K_CG_EVENT_MOUSE_MOVED: u32 = 5;
const K_CG_EVENT_LEFT_MOUSE_DRAGGED: u32 = 6;
const K_CG_EVENT_TAP_DISABLED_BY_TIMEOUT: u32 = 0xFFFF_FFFE;
const K_CG_EVENT_TAP_DISABLED_BY_USER_INPUT: u32 = 0xFFFF_FFFF;
const K_CG_WINDOW_LIST_OPTION_ON_SCREEN_ONLY: u32 = 1;
const K_CF_STRING_ENCODING_UTF8: u32 = 0x0800_0100;
const K_CF_NUMBER_SINT32_TYPE: isize = 3;

#[repr(C)]
#[derive(Copy, Clone, Default)]
struct CGPoint {
    x: f64,
    y: f64,
}

type TapCallback = extern "C" fn(*mut c_void, u32, *mut c_void, *mut c_void) -> *mut c_void;

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: u64,
        callback: TapCallback,
        user_info: *mut c_void,
    ) -> *mut c_void;
    fn CGEventTapEnable(tap: *mut c_void, enable: bool);
    fn CGEventGetLocation(event: *mut c_void) -> CGPoint;
    fn CGWindowListCopyWindowInfo(option: u32, relative_to: u32) -> *const c_void;
    static kCGWindowOwnerName: *const c_void;
    static kCGWindowLayer: *const c_void;
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(cf: *const c_void);
    fn CFMachPortCreateRunLoopSource(
        alloc: *const c_void,
        port: *mut c_void,
        order: isize,
    ) -> *mut c_void;
    fn CFRunLoopGetCurrent() -> *mut c_void;
    fn CFRunLoopAddSource(rl: *mut c_void, source: *mut c_void, mode: *const c_void);
    fn CFRunLoopRun();
    static kCFRunLoopCommonModes: *const c_void;
    fn CFArrayGetCount(array: *const c_void) -> isize;
    fn CFArrayGetValueAtIndex(array: *const c_void, idx: isize) -> *const c_void;
    fn CFDictionaryGetValue(dict: *const c_void, key: *const c_void) -> *const c_void;
    fn CFStringGetCString(s: *const c_void, buf: *mut c_char, size: isize, enc: u32) -> bool;
    fn CFNumberGetValue(n: *const c_void, kind: isize, out: *mut c_void) -> bool;
    fn CFStringCreateWithCString(alloc: *const c_void, s: *const c_char, enc: u32) -> *const c_void;
    fn CFNotificationCenterGetDistributedCenter() -> *const c_void;
    fn CFNotificationCenterPostNotification(
        center: *const c_void,
        name: *const c_void,
        object: *const c_void,
        user_info: *const c_void,
        deliver_immediately: bool,
    );
}

/// Announced on every replayed click. The press itself is swallowed, so other
/// apps' click-outside monitors (BarPanels panels, in screenshare-ui and
/// Virtual Headset) never see it; they close on this instead.
const BAR_CLICKED: &CStr = c"bar-panels.bar-clicked";

fn announce_click() {
    // SAFETY: the CFString is created from a static C string and released
    // after posting; the distributed center is a process-wide singleton.
    unsafe {
        let name = CFStringCreateWithCString(
            std::ptr::null(),
            BAR_CLICKED.as_ptr(),
            K_CF_STRING_ENCODING_UTF8,
        );
        if name.is_null() {
            return;
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            name,
            std::ptr::null(),
            std::ptr::null(),
            true,
        );
        CFRelease(name);
    }
}

#[derive(Debug, Clone, Copy)]
enum MouseEvent {
    Moved(f64, f64),
    Down(f64, f64),
    Up(f64, f64),
}

static EVENTS: OnceLock<Sender<MouseEvent>> = OnceLock::new();
static TAP: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());

/// What sits over sketchybar, i.e. whether its own mouse events reach it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Cover {
    /// Nothing: sketchybar gets its events (or the native bar is revealed by
    /// the user, and its clicks are the user's).
    None,
    /// MenuBarAgent's reveal window.
    Overlay,
    /// menubar-reveal holding the native bar revealed but transparent.
    Held,
}

/// What the tap callback needs to decide on the spot whether to swallow a
/// press, as last seen by the tracker thread.
struct Snapshot {
    cover: Cover,
    bar_bottom: f64,
    rects: Vec<Rect>,
}

static SNAPSHOT: Mutex<Snapshot> = Mutex::new(Snapshot {
    cover: Cover::None,
    bar_bottom: 0.0,
    rects: Vec::new(),
});
/// Set while a swallowed press's release is still to come.
static SWALLOWING: AtomicBool = AtomicBool::new(false);

fn swallow_press(x: f64, y: f64) -> bool {
    let s = SNAPSHOT.lock().unwrap_or_else(|e| e.into_inner());
    match s.cover {
        Cover::None => false,
        Cover::Overlay => s.rects.iter().any(|r| r.contains(x, y)),
        Cover::Held => y <= s.bar_bottom,
    }
}

extern "C" fn tap_callback(
    _proxy: *mut c_void,
    kind: u32,
    event: *mut c_void,
    _user: *mut c_void,
) -> *mut c_void {
    if kind == K_CG_EVENT_TAP_DISABLED_BY_TIMEOUT || kind == K_CG_EVENT_TAP_DISABLED_BY_USER_INPUT
    {
        let tap = TAP.load(Ordering::Acquire);
        if !tap.is_null() {
            // SAFETY: `tap` is the live mach port created in `run_tap`.
            unsafe { CGEventTapEnable(tap, true) };
        }
        return event;
    }
    // SAFETY: for mouse event kinds `event` is a valid CGEventRef owned by
    // the tap for the duration of the callback.
    let p = unsafe { CGEventGetLocation(event) };
    let (ev, swallow) = match kind {
        K_CG_EVENT_MOUSE_MOVED | K_CG_EVENT_LEFT_MOUSE_DRAGGED => {
            (MouseEvent::Moved(p.x, p.y), false)
        }
        K_CG_EVENT_LEFT_MOUSE_DOWN => {
            let hit = swallow_press(p.x, p.y);
            SWALLOWING.store(hit, Ordering::Relaxed);
            (MouseEvent::Down(p.x, p.y), hit)
        }
        K_CG_EVENT_LEFT_MOUSE_UP => (
            MouseEvent::Up(p.x, p.y),
            SWALLOWING.swap(false, Ordering::Relaxed),
        ),
        _ => return event,
    };
    if let Some(tx) = EVENTS.get() {
        let _ = tx.send(ev);
    }
    if swallow {
        std::ptr::null_mut()
    } else {
        event
    }
}

/// Create the tap (active if trusted, else listen-only) and run its run loop
/// on the current thread.
fn run_tap() {
    let mask = (1u64 << K_CG_EVENT_LEFT_MOUSE_DOWN)
        | (1u64 << K_CG_EVENT_LEFT_MOUSE_UP)
        | (1u64 << K_CG_EVENT_MOUSE_MOVED)
        | (1u64 << K_CG_EVENT_LEFT_MOUSE_DRAGGED);
    // SAFETY: plain CoreGraphics/CoreFoundation calls; every pointer is
    // null-checked before use and the port/source live for the process.
    unsafe {
        let create = |option| {
            CGEventTapCreate(
                K_CG_SESSION_EVENT_TAP,
                K_CG_HEAD_INSERT_EVENT_TAP,
                option,
                mask,
                tap_callback,
                std::ptr::null_mut(),
            )
        };
        let mut tap = create(K_CG_EVENT_TAP_OPTION_DEFAULT);
        if tap.is_null() {
            eprintln!(
                "sketchybar-hoverd: no Accessibility trust for an active tap; \
                 bar clicks will reveal the native menu bar"
            );
            tap = create(K_CG_EVENT_TAP_OPTION_LISTEN_ONLY);
        }
        if tap.is_null() {
            eprintln!("sketchybar-hoverd: CGEventTapCreate failed; covered-bar hover/clicks disabled");
            return;
        }
        TAP.store(tap, Ordering::Release);
        let source = CFMachPortCreateRunLoopSource(std::ptr::null(), tap, 0);
        if source.is_null() {
            eprintln!("sketchybar-hoverd: CFMachPortCreateRunLoopSource failed");
            return;
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        CFRunLoopRun();
    }
}

fn cf_string(s: *const c_void) -> Option<String> {
    if s.is_null() {
        return None;
    }
    let mut buf = [0 as c_char; 256];
    // SAFETY: `s` is a CFStringRef from a window-info dictionary; `buf` is
    // large enough for any process name and is NUL-terminated on success.
    unsafe {
        if !CFStringGetCString(s, buf.as_mut_ptr(), buf.len() as isize, K_CF_STRING_ENCODING_UTF8)
        {
            return None;
        }
        Some(CStr::from_ptr(buf.as_ptr()).to_string_lossy().into_owned())
    }
}

/// What covers sketchybar right now, from the on-screen window list.
fn current_cover() -> Cover {
    // SAFETY: the returned CFArray is owned by us and released below; the
    // dictionaries and values inside it are borrowed from it.
    unsafe {
        let list = CGWindowListCopyWindowInfo(K_CG_WINDOW_LIST_OPTION_ON_SCREEN_ONLY, 0);
        if list.is_null() {
            return Cover::None;
        }
        let mut cover = Cover::None;
        for i in 0..CFArrayGetCount(list) {
            let info = CFArrayGetValueAtIndex(list, i);
            let mut layer: i32 = 0;
            let layer_ref = CFDictionaryGetValue(info, kCGWindowLayer);
            if !layer_ref.is_null()
                && CFNumberGetValue(
                    layer_ref,
                    K_CF_NUMBER_SINT32_TYPE,
                    &mut layer as *mut i32 as *mut c_void,
                )
                && layer == OVERLAY_LAYER
                && cf_string(CFDictionaryGetValue(info, kCGWindowOwnerName)).as_deref()
                    == Some(OVERLAY_OWNER)
            {
                cover = Cover::Overlay;
                break;
            }
        }
        CFRelease(list);
        if cover == Cover::None && hold_active() {
            return Cover::Held;
        }
        cover
    }
}

unsafe extern "C" {
    fn notify_register_check(name: *const c_char, token: *mut i32) -> u32;
    fn notify_get_state(token: i32, state: *mut u64) -> u32;
    fn kill(pid: i32, sig: i32) -> i32;
}

/// Whether a live menubar-reveal says it's holding the native bar transparent.
fn hold_active() -> bool {
    static TOKEN: OnceLock<Option<i32>> = OnceLock::new();
    let token = *TOKEN.get_or_init(|| {
        let mut t = 0;
        // SAFETY: a static C string and an out-pointer to a local.
        (unsafe { notify_register_check(HOLD_KEY.as_ptr(), &mut t) } == 0).then_some(t)
    });
    let Some(token) = token else { return false };
    let mut pid = 0u64;
    // SAFETY: a registered token and an out-pointer to a local; kill with
    // signal 0 only checks that the pid exists.
    unsafe { notify_get_state(token, &mut pid) == 0 && pid != 0 && kill(pid as i32, 0) == 0 }
}

#[derive(Debug, Clone, PartialEq)]
struct Rect {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

impl Rect {
    fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

#[derive(Debug, Clone)]
struct Item {
    name: String,
    rects: Vec<Rect>,
    click_script: Option<String>,
    script: Option<String>,
    subscribes_clicked: bool,
}

fn sketchybar_query(target: &str) -> Option<serde_json::Value> {
    let out = Command::new("sketchybar")
        .args(["--query", target])
        .stderr(Stdio::null())
        .output()
        .ok()?;
    serde_json::from_slice(&out.stdout).ok()
}

fn non_null_script(v: &serde_json::Value) -> Option<String> {
    v.as_str()
        .filter(|s| !s.is_empty() && *s != "(null)")
        .map(String::from)
}

fn parse_item(v: &serde_json::Value) -> Option<Item> {
    let name = v.get("name")?.as_str()?.to_string();
    if v.pointer("/geometry/drawing").and_then(|d| d.as_str()) == Some("off") {
        return None;
    }
    let rects: Vec<Rect> = v
        .get("bounding_rects")?
        .as_object()?
        .values()
        .filter_map(|r| {
            let origin = r.get("origin")?.as_array()?;
            let size = r.get("size")?.as_array()?;
            Some(Rect {
                x: origin.first()?.as_f64()?,
                y: origin.get(1)?.as_f64()?,
                w: size.first()?.as_f64()?,
                h: size.get(1)?.as_f64()?,
            })
        })
        .filter(|r| r.w > 0.0 && r.h > 0.0)
        .collect();
    if rects.is_empty() {
        return None;
    }
    let scripting = v.get("scripting");
    let field = |k: &str| scripting.and_then(|s| s.get(k)).and_then(non_null_script);
    let mask = scripting
        .and_then(|s| s.get("update_mask"))
        .and_then(|m| m.as_u64())
        .unwrap_or(0);
    Some(Item {
        name,
        rects,
        click_script: field("click_script"),
        script: field("script"),
        subscribes_clicked: mask & MOUSE_CLICKED_BIT != 0,
    })
}

fn query_items() -> Vec<Item> {
    let Some(bar) = sketchybar_query("bar") else {
        return Vec::new();
    };
    let names: Vec<String> = bar
        .get("items")
        .and_then(|i| i.as_array())
        .map(|a| a.iter().filter_map(|n| n.as_str().map(String::from)).collect())
        .unwrap_or_default();
    names
        .iter()
        .filter_map(|n| sketchybar_query(n))
        .filter_map(|v| parse_item(&v))
        .collect()
}

fn hit(items: &[Item], x: f64, y: f64) -> Option<&Item> {
    items
        .iter()
        .find(|i| i.rects.iter().any(|r| r.contains(x, y)))
}

fn config_dir() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    format!("{home}/.config/sketchybar")
}

/// Run `cmd` the way sketchybar runs item scripts: `sh -c` from the config
/// dir with the click environment. Reaped on a throwaway thread.
fn spawn_script(cmd: &str, name: &str, sender: &str) {
    let dir = config_dir();
    let child = Command::new("/bin/sh")
        .arg("-c")
        .arg(cmd)
        .current_dir(&dir)
        .env("NAME", name)
        .env("SENDER", sender)
        .env("BUTTON", "left")
        .env("MODIFIER", "none")
        .env("CONFIG_DIR", &dir)
        .env("BAR_NAME", "sketchybar")
        .stdin(Stdio::null())
        .spawn();
    match child {
        Ok(mut c) => {
            thread::spawn(move || {
                let _ = c.wait();
            });
        }
        Err(e) => eprintln!("sketchybar-hoverd: click script for {name} failed: {e}"),
    }
}

fn click(item: &Item) {
    announce_click();
    if let Some(cs) = &item.click_script {
        spawn_script(cs, &item.name, "mouse.clicked");
    }
    if item.subscribes_clicked {
        if let Some(s) = &item.script {
            spawn_script(s, &item.name, "mouse.clicked");
        }
    }
}

struct Tracker {
    items: Vec<Item>,
    items_at: Option<Instant>,
    cover: Cover,
    cover_at: Option<Instant>,
    in_bar: bool,
    hovered: Option<String>,
    pressed: Option<String>,
    pressed_in_bar: bool,
}

impl Tracker {
    fn items(&mut self, max_age: Duration) -> &[Item] {
        if self.items_at.is_none_or(|t| t.elapsed() > max_age) {
            self.items = query_items();
            self.items_at = Some(Instant::now());
            let rects = self.items.iter().flat_map(|i| i.rects.clone()).collect();
            SNAPSHOT.lock().unwrap_or_else(|e| e.into_inner()).rects = rects;
        }
        &self.items
    }

    fn cover(&mut self, max_age: Duration) -> Cover {
        if self.cover_at.is_none_or(|t| t.elapsed() > max_age) {
            self.cover = current_cover();
            self.cover_at = Some(Instant::now());
            SNAPSHOT.lock().unwrap_or_else(|e| e.into_inner()).cover = self.cover;
        }
        self.cover
    }

    fn set_hover(&mut self, next: Option<String>, emit: &dyn Fn(HoverEvent)) {
        if self.hovered == next {
            return;
        }
        match &next {
            Some(n) => emit(HoverEvent::Enter(n.clone())),
            None => emit(HoverEvent::ExitAll),
        }
        self.hovered = next;
    }

    fn handle(&mut self, ev: MouseEvent, bar_bottom: f64, emit: &dyn Fn(HoverEvent)) {
        let (x, y) = match ev {
            MouseEvent::Moved(x, y) | MouseEvent::Down(x, y) | MouseEvent::Up(x, y) => (x, y),
        };
        let entering = !self.in_bar;
        self.in_bar = y <= bar_bottom;
        if !self.in_bar {
            self.pressed = None;
            self.set_hover(None, emit);
            return;
        }
        let fresh = Duration::ZERO;
        let cover_age = if matches!(ev, MouseEvent::Moved(..)) && !entering {
            COVER_MAX_AGE
        } else {
            fresh
        };
        let cover = self.cover(cover_age);
        if cover == Cover::None {
            self.pressed = None;
            self.pressed_in_bar = false;
            self.set_hover(None, emit);
            return;
        }
        match ev {
            MouseEvent::Moved(..) => {
                let max_age = if entering { fresh } else { GEOMETRY_MAX_AGE };
                let name = hit(self.items(max_age), x, y).map(|i| i.name.clone());
                self.set_hover(name, emit);
            }
            MouseEvent::Down(..) => {
                self.pressed = hit(self.items(CLICK_GEOMETRY_MAX_AGE), x, y).map(|i| i.name.clone());
                self.pressed_in_bar = true;
            }
            MouseEvent::Up(..) => {
                let in_bar = std::mem::take(&mut self.pressed_in_bar);
                let pressed = self.pressed.take();
                let item = hit(self.items(CLICK_GEOMETRY_MAX_AGE), x, y)
                    .filter(|i| pressed.as_deref() == Some(i.name.as_str()));
                match item {
                    Some(item) => click(item),
                    // A swallowed press off the items still closes the popover.
                    None if in_bar && cover == Cover::Held => announce_click(),
                    None => {}
                }
            }
        }
    }
}

fn track(rx: Receiver<MouseEvent>, bar_bottom: f64, emit: Box<dyn Fn(HoverEvent) + Send>) {
    let mut t = Tracker {
        items: Vec::new(),
        items_at: None,
        cover: Cover::None,
        cover_at: None,
        in_bar: false,
        hovered: None,
        pressed: None,
        pressed_in_bar: false,
    };
    while let Ok(mut ev) = rx.recv() {
        // Collapse a backlog of moves to the latest position; never drop
        // presses or releases.
        while let MouseEvent::Moved(..) = ev {
            match rx.try_recv() {
                Ok(next) => ev = next,
                Err(_) => break,
            }
        }
        t.handle(ev, bar_bottom, &*emit);
    }
}

/// Start the tap and tracker threads. `emit` feeds hover events into the
/// daemon's state machine.
pub fn spawn(bar_bottom: f64, emit: Box<dyn Fn(HoverEvent) + Send>) {
    let (tx, rx) = mpsc::channel();
    if EVENTS.set(tx).is_err() {
        return;
    }
    SNAPSHOT.lock().unwrap_or_else(|e| e.into_inner()).bar_bottom = bar_bottom;
    thread::Builder::new()
        .name("tap-tracker".into())
        .spawn(move || track(rx, bar_bottom, emit))
        .expect("spawn tap tracker");
    thread::Builder::new()
        .name("tap-runloop".into())
        .spawn(run_tap)
        .expect("spawn tap run loop");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_item_query() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"name":"wifi","geometry":{"drawing":"on"},
                "scripting":{"script":"sketchybar-hover --plugin plugins/wifi.nu",
                  "click_script":"x.nu \"Wi-Fi\"","update_mask":32816},
                "bounding_rects":{"display-1":{"origin":[1203.0,0.0],"size":[26.0,32.0]}}}"#,
        )
        .unwrap();
        let item = parse_item(&v).unwrap();
        assert_eq!(item.name, "wifi");
        assert_eq!(item.click_script.as_deref(), Some("x.nu \"Wi-Fi\""));
        assert!(!item.subscribes_clicked);
        assert!(item.rects[0].contains(1210.0, 5.0));
        assert!(!item.rects[0].contains(1229.0, 5.0));
    }

    #[test]
    fn null_click_script_and_clicked_bit() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"name":"hidewin","scripting":{"script":"s","click_script":"(null)","update_mask":524400},
                "bounding_rects":{"display-1":{"origin":[1116.0,0.0],"size":[26.0,32.0]}}}"#,
        )
        .unwrap();
        let item = parse_item(&v).unwrap();
        assert_eq!(item.click_script, None);
        assert!(item.subscribes_clicked);
    }

    #[test]
    fn hidden_or_unplaced_items_are_skipped() {
        let hidden: serde_json::Value = serde_json::from_str(
            r#"{"name":"a","geometry":{"drawing":"off"},
                "bounding_rects":{"display-1":{"origin":[0,0],"size":[10,10]}}}"#,
        )
        .unwrap();
        let unplaced: serde_json::Value =
            serde_json::from_str(r#"{"name":"b","bounding_rects":{}}"#).unwrap();
        assert!(parse_item(&hidden).is_none());
        assert!(parse_item(&unplaced).is_none());
    }
}
