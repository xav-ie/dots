//! Persistent daemon that owns sketchybar's per-item hover state.
//!
//! - Listens on a Unix socket for ENTER/EXIT/EXIT_ALL lines from the
//!   `sketchybar-hover` client.
//! - Maintains the invariant: at most one item hovered at any time. Any new
//!   ENTER preemptively unhovers the previous item — this is the workaround
//!   for sketchybar occasionally dropping `mouse.exited`.
//! - Batches every state change into a single `sketchybar --set ... --set ...`
//!   invocation so the bar updates atomically.
//! - Polling fallback: when something is hovered, every 250 ms read the global
//!   mouse position via CoreGraphics; if the cursor has left the bar's
//!   y-range, force-unhover. Catches the rare case where both the
//!   per-item exit and the `mouse.exited.global` get dropped.

use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::io::{self, BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::process::Command;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use sketchybar_hover::{HoverEvent, SOCKET_PATH};

const HOVER_COLOR: &str = "0x33ffffff";
const CLEAR_COLOR: &str = "0x00000000";

/// Set `SKETCHYBAR_HOVER_DEBUG=1` in the daemon's environment to log every
/// event, state transition, and sketchybar invocation to stderr (which lands
/// in /tmp/sketchybar-hover.err under launchd). Off by default.
fn debug_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        std::env::var("SKETCHYBAR_HOVER_DEBUG")
            .map(|v| !v.is_empty() && v != "0")
            .unwrap_or(false)
    })
}

macro_rules! debug_log {
    ($($arg:tt)*) => {
        if debug_enabled() {
            eprintln!("[hoverd] {}", format_args!($($arg)*));
        }
    };
}

// Hover bg animation. Sketchybar interpolates from the current bg color to
// the target over N frames at 60 fps; if a sweep preempts before N frames
// elapse, peak opacity is whatever the interpolation reached. 12 frames ≈
// 200ms matches fade-in to fade-out. Anything below ~3 frames risks the
// renderer coalescing back-to-back ON+OFF into a single frame.
const ANIMATE_CURVE_ON: &str = "sin";
const ANIMATE_FRAMES_ON: &str = "6";
const ANIMATE_CURVE_OFF: &str = "sin";
const ANIMATE_FRAMES_OFF: &str = "18";

// Bar geometry, used only by the polling fallback. Read from the
// SKETCHYBAR_BAR_HEIGHT env var, which the launchd agent sources from the
// `barHeight` Nix binding in home-manager/darwin/sketchybar/default.nix —
// the same binding feeds `(get_bar_height)` in sketchybarrc.nu, so all three
// places track one value. Falls back to 32 if the env var is missing.
const BAR_BOTTOM_Y_FALLBACK: f64 = 32.0;
const POLL_INTERVAL: Duration = Duration::from_millis(250);

fn bar_bottom_y() -> f64 {
    static V: OnceLock<f64> = OnceLock::new();
    *V.get_or_init(|| {
        std::env::var("SKETCHYBAR_BAR_HEIGHT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(BAR_BOTTOM_Y_FALLBACK)
    })
}

// Debounce window for honoring `mouse.exited`. Crossing the boundary between
// items that share a target (e.g. clock label ↔ clock_icon) fires EXIT on the
// old item shortly before ENTER on the new one; debouncing lets the ENTER
// cancel the pending EXIT and avoid an unhover/rehover flash.
const EXIT_DEBOUNCE: Duration = Duration::from_millis(40);

// Minimum visible time between issuing a target's hover-on and its hover-off.
// When ENTER preempts a recently-painted target, we defer the OFF until at
// least this much wall-clock has elapsed since the ON, so the fade-in always
// completes and the fade-out animates from full opacity. Should match
// ANIMATE_FRAMES_ON at 60 fps.
const MIN_ON_DURATION: Duration = Duration::from_millis(100);

#[repr(C)]
#[derive(Copy, Clone, Default)]
struct CGPoint {
    x: f64,
    y: f64,
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGEventCreate(source: *const c_void) -> *mut c_void;
    fn CGEventGetLocation(event: *mut c_void) -> CGPoint;
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(cf: *const c_void);
}

// macOS declares `mode_t` as `__uint16_t` in <sys/_types.h>. Using `u16`
// matches the actual ABI rather than relying on register-width zero-extension
// to make a `u32` declaration accidentally work.
#[allow(non_camel_case_types)]
type mode_t = u16;
unsafe extern "C" {
    fn umask(mask: mode_t) -> mode_t;
}

fn mouse_location() -> Option<CGPoint> {
    // SAFETY: passing a NULL source to CGEventCreate is valid; the returned
    // CFTypeRef is released below.
    unsafe {
        let event = CGEventCreate(std::ptr::null());
        if event.is_null() {
            return None;
        }
        let p = CGEventGetLocation(event);
        CFRelease(event as *const c_void);
        Some(p)
    }
}

/// Subscribed item name → target item that gets the background-color change.
/// Multiple names can share a target (e.g. `clock` and `clock_icon` both
/// paint onto `clock`).
type NameToTarget = HashMap<&'static str, &'static str>;

/// Target item → property keys to set when painting on/off. Keys live with
/// the target rather than the subscribed name so two names sharing a target
/// can't disagree on which properties to flip.
type TargetKeys = HashMap<&'static str, &'static [&'static str]>;

fn item_configs() -> (NameToTarget, TargetKeys) {
    let clock_keys: &[&str] = &["label.background.color", "icon.background.color"];
    let label_only: &[&str] = &["label.background.color"];
    let icon_only: &[&str] = &["icon.background.color"];
    // The wifi icon is an image with no label, so it paints its own item
    // background (see wifi.nu) rather than a sibling highlight item.
    let bg_only: &[&str] = &["background.color"];

    let name_to_target: NameToTarget = HashMap::from([
        ("clock", "clock"),
        ("clock_icon", "clock"),
        ("front_app", "front_app"),
        ("wifi", "wifi"),
        ("control_center", "control_center"),
        ("battery", "battery"),
        ("battery_icon", "battery"),
        ("volume", "volume"),
        ("volume_icon", "volume"),
    ]);
    let target_keys: TargetKeys = HashMap::from([
        ("clock", clock_keys),
        ("front_app", label_only),
        ("wifi", bg_only),
        ("control_center", icon_only),
        ("battery", label_only),
        ("volume", label_only),
    ]);
    (name_to_target, target_keys)
}

struct State {
    /// Subscribed item names currently believed to be hovered. Each name's
    /// presence is driven by its own ENTER/EXIT, with cross-target ENTERs
    /// preempting stale names (cursor can only be over one item physically).
    hovered_names: HashSet<String>,
    /// Targets we've issued a hover-on for and not yet issued a hover-off
    /// for. A target stays here until both (a) it's no longer in `desired`
    /// and (b) `MIN_ON_DURATION` has elapsed since its ON.
    rendered_targets: HashSet<String>,
    /// Wall-clock time when each rendered target's ON was issued. Drives the
    /// MIN_ON_DURATION enforcement so brief preempted hovers still animate
    /// to full opacity before fading out.
    target_on_at: HashMap<String, Instant>,
    /// Targets that already have a deferred-OFF thread sleeping. Keeps a
    /// fast sweep from spawning duplicate timers per target.
    pending_off_for: HashSet<String>,
    name_to_target: NameToTarget,
    target_keys: TargetKeys,
    /// Per-name generation, bumped on every ENTER for that name AND on every
    /// preemption that drops the name. Debounced EXITs capture the gen at
    /// scheduling time and only fire if it hasn't moved (no fresh ENTER for
    /// the same name) by the time the debounce elapses.
    name_gen: HashMap<String, u64>,
}

/// Identifier for a name whose EXIT has been scheduled with a debounce.
struct PendingRemoval {
    name: String,
    generation: u64,
}

/// Identifier for a target whose hover-off has been deferred until its
/// fade-in had time to complete.
struct DeferredOff {
    target: String,
    fire_at: Instant,
}

impl State {
    fn apply_enter(&mut self, name: String) -> (Vec<String>, Vec<DeferredOff>) {
        let Some(target) = self.name_to_target.get(name.as_str()).copied() else {
            return (Vec::new(), Vec::new());
        };
        // Preempt: drop names targeting a different item. The cursor can only
        // be over one physical item, so different-target names must be stale
        // (e.g. their EXIT was dropped). Same-target names (label + icon)
        // stay so the bg keeps rendering during a label↔icon crossing. Bump
        // gen on every dropped name so any debounced EXIT for those names
        // sees a stale generation when it wakes up and bails out cleanly.
        let preempted: Vec<String> = self
            .hovered_names
            .iter()
            .filter(|n| self.name_to_target.get(n.as_str()).copied() != Some(target))
            .cloned()
            .collect();
        for n in &preempted {
            self.hovered_names.remove(n);
            *self.name_gen.entry(n.clone()).or_insert(0) += 1;
        }
        *self.name_gen.entry(name.clone()).or_insert(0) += 1;
        self.hovered_names.insert(name);
        self.reconcile()
    }

    fn apply_exit_all(&mut self) -> (Vec<String>, Vec<DeferredOff>) {
        self.hovered_names.clear();
        self.reconcile()
    }

    /// Snapshot the data needed to schedule a debounced EXIT. Returns None if
    /// the name isn't currently in the hovered set.
    fn snapshot_exit(&self, name: &str) -> Option<PendingRemoval> {
        if !self.hovered_names.contains(name) {
            return None;
        }
        Some(PendingRemoval {
            name: name.to_string(),
            generation: self.name_gen.get(name).copied().unwrap_or(0),
        })
    }

    /// Fire a previously-scheduled removal for `name`, aborting if a fresh
    /// ENTER for the same name has arrived since.
    fn try_apply_pending_removal(
        &mut self,
        name: &str,
        generation: u64,
    ) -> (Vec<String>, Vec<DeferredOff>) {
        let current = self.name_gen.get(name).copied().unwrap_or(0);
        if current != generation {
            return (Vec::new(), Vec::new());
        }
        self.hovered_names.remove(name);
        self.reconcile()
    }

    /// Fire a previously-scheduled deferred OFF for `target`. Skipped if the
    /// target is hovered again, or already removed (e.g. by an earlier defer
    /// for the same target). Always clears the pending-off flag so future
    /// preempts can schedule fresh defers.
    fn try_apply_deferred_off(&mut self, target: &str) -> Vec<String> {
        self.pending_off_for.remove(target);
        let still_hovered = self
            .hovered_names
            .iter()
            .any(|n| self.name_to_target.get(n.as_str()).copied() == Some(target));
        if still_hovered {
            return Vec::new();
        }
        if !self.rendered_targets.contains(target) {
            return Vec::new();
        }
        let mut args = Vec::new();
        self.append_set(&mut args, target, false);
        self.rendered_targets.remove(target);
        self.target_on_at.remove(target);
        args
    }

    fn reconcile(&mut self) -> (Vec<String>, Vec<DeferredOff>) {
        let desired: HashSet<String> = self
            .hovered_names
            .iter()
            .filter_map(|n| {
                self.name_to_target
                    .get(n.as_str())
                    .copied()
                    .map(String::from)
            })
            .collect();

        let to_off: Vec<String> = self
            .rendered_targets
            .difference(&desired)
            .cloned()
            .collect();
        let to_on: Vec<String> = desired
            .difference(&self.rendered_targets)
            .cloned()
            .collect();

        let mut args = Vec::new();
        let mut deferred = Vec::new();
        let now = Instant::now();
        for t in &to_off {
            let elapsed = self
                .target_on_at
                .get(t)
                .map(|on_at| now.saturating_duration_since(*on_at))
                .unwrap_or(MIN_ON_DURATION);
            if elapsed >= MIN_ON_DURATION {
                self.append_set(&mut args, t, false);
                self.rendered_targets.remove(t);
                self.target_on_at.remove(t);
                // Clear any stale pending-off marker so the invariant
                // "flag set ⇔ a deferred-off thread is sleeping for this
                // target" holds without relying on the timer to wake.
                self.pending_off_for.remove(t);
            } else if !self.pending_off_for.contains(t) {
                // Defer the OFF until the fade-in has completed. Keep the
                // target in `rendered_targets` so subsequent ENTERs see it as
                // already painted (no flicker when the user re-hovers it).
                // Skip if a defer is already in flight for this target —
                // it'll handle this preemption when it wakes up.
                let fire_at = self
                    .target_on_at
                    .get(t)
                    .copied()
                    .map(|on_at| on_at + MIN_ON_DURATION)
                    .unwrap_or_else(|| now + MIN_ON_DURATION);
                self.pending_off_for.insert(t.clone());
                deferred.push(DeferredOff {
                    target: t.clone(),
                    fire_at,
                });
            }
        }
        for t in &to_on {
            self.append_set(&mut args, t, true);
            self.rendered_targets.insert(t.clone());
            self.target_on_at.insert(t.clone(), now);
        }
        (args, deferred)
    }

    fn append_set(&self, args: &mut Vec<String>, target: &str, on: bool) {
        let Some(keys) = self.target_keys.get(target).copied() else {
            return;
        };
        let color = if on { HOVER_COLOR } else { CLEAR_COLOR };
        let (curve, frames) = if on {
            (ANIMATE_CURVE_ON, ANIMATE_FRAMES_ON)
        } else {
            (ANIMATE_CURVE_OFF, ANIMATE_FRAMES_OFF)
        };
        args.push("--animate".into());
        args.push(curve.into());
        args.push(frames.into());
        args.push("--set".into());
        args.push(target.into());
        for key in keys {
            args.push(format!("{key}={color}"));
        }
    }
}

fn dispatch(state: &Arc<Mutex<State>>, tx: &Sender<Vec<String>>, event: HoverEvent) {
    debug_log!("event {event:?}");
    match event {
        HoverEvent::Enter(name) => {
            let mut s = state.lock().expect("state mutex poisoned");
            let (args, deferred) = s.apply_enter(name);
            debug_log!(
                "after ENTER: hovered={:?} rendered={:?}",
                s.hovered_names,
                s.rendered_targets
            );
            // Send under the lock so that two events serialized on the
            // mutex also serialize at the worker's mpsc receiver.
            let _ = tx.send(args);
            spawn_deferred_offs(state, tx, deferred);
        }
        HoverEvent::ExitAll => {
            let mut s = state.lock().expect("state mutex poisoned");
            let (args, deferred) = s.apply_exit_all();
            debug_log!(
                "after EXIT_ALL: hovered={:?} rendered={:?}",
                s.hovered_names,
                s.rendered_targets
            );
            let _ = tx.send(args);
            spawn_deferred_offs(state, tx, deferred);
        }
        HoverEvent::Exit(name) => {
            let pending = {
                let s = state.lock().expect("state mutex poisoned");
                s.snapshot_exit(&name)
            };
            let Some(pending) = pending else {
                debug_log!("EXIT {name} dropped (not in hovered set)");
                return;
            };
            debug_log!("EXIT {name} scheduled (gen={})", pending.generation);
            let state_clone = Arc::clone(state);
            let tx_clone = tx.clone();
            thread::spawn(move || {
                thread::sleep(EXIT_DEBOUNCE);
                let mut s = state_clone.lock().expect("state mutex poisoned");
                let (args, deferred) =
                    s.try_apply_pending_removal(&pending.name, pending.generation);
                debug_log!(
                    "EXIT {} fired: hovered={:?} rendered={:?}",
                    pending.name,
                    s.hovered_names,
                    s.rendered_targets
                );
                let _ = tx_clone.send(args);
                spawn_deferred_offs(&state_clone, &tx_clone, deferred);
            });
        }
    }
}

fn spawn_deferred_offs(
    state: &Arc<Mutex<State>>,
    tx: &Sender<Vec<String>>,
    deferred: Vec<DeferredOff>,
) {
    for d in deferred {
        let state = Arc::clone(state);
        let tx = tx.clone();
        thread::spawn(move || {
            let now = Instant::now();
            if d.fire_at > now {
                thread::sleep(d.fire_at - now);
            }
            let mut s = state.lock().expect("state mutex poisoned");
            let args = s.try_apply_deferred_off(&d.target);
            debug_log!(
                "deferred OFF {}: hovered={:?} rendered={:?}",
                d.target,
                s.hovered_names,
                s.rendered_targets
            );
            let _ = tx.send(args);
        });
    }
}

/// Serializes all sketchybar invocations on a single thread so they fire in
/// the order their args were produced, regardless of where (accept loop,
/// poll loop, or an EXIT debounce thread) they came from.
fn sketchybar_worker(rx: mpsc::Receiver<Vec<String>>) {
    while let Ok(args) = rx.recv() {
        if args.is_empty() {
            continue;
        }
        debug_log!("sketchybar {}", args.join(" "));
        match Command::new("sketchybar").args(&args).status() {
            Ok(s) if !s.success() => {
                eprintln!("sketchybar-hoverd: sketchybar exited {s}");
            }
            Err(e) => {
                eprintln!("sketchybar-hoverd: sketchybar invocation failed: {e}");
            }
            Ok(_) => {}
        }
    }
}

fn handle_client(state: Arc<Mutex<State>>, tx: Sender<Vec<String>>, conn: UnixStream) {
    // The single-threaded accept loop means a stuck client would freeze the
    // daemon; cap the per-line read so we move on quickly if a client hangs.
    let _ = conn.set_read_timeout(Some(Duration::from_millis(50)));
    let reader = BufReader::new(conn);
    for line in reader.lines() {
        match line {
            Ok(l) => {
                if let Some(event) = HoverEvent::parse(&l) {
                    dispatch(&state, &tx, event);
                }
            }
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) =>
            {
                debug_log!("client read timed out, dropping connection");
                return;
            }
            Err(_) => return,
        }
    }
}

fn poll_loop(state: Arc<Mutex<State>>, tx: Sender<Vec<String>>) {
    loop {
        thread::sleep(POLL_INTERVAL);

        // Snapshot under the lock, then release before the CG syscall —
        // CGEventCreate does an IPC round-trip to WindowServer that can
        // take low-single-digit ms under load, and we don't want every
        // accept/debounce/defer thread blocked behind it.
        let must_check = {
            let s = state.lock().expect("state mutex poisoned");
            !s.rendered_targets.is_empty()
        };
        if !must_check {
            continue;
        }
        let Some(p) = mouse_location() else { continue };
        if p.y <= bar_bottom_y() {
            continue;
        }

        let mut s = state.lock().expect("state mutex poisoned");
        // Re-check: another thread may have cleared hover state while we
        // were querying the cursor.
        if s.rendered_targets.is_empty() {
            continue;
        }
        // Re-query CG under the lock so a fresh ENTER that landed between
        // the first cursor read and re-acquiring the lock isn't clobbered.
        // Worst case is one CG roundtrip held under the lock at 250ms
        // cadence and only when something is hovered + cursor was below
        // the bar at first read; the common path stays lock-free.
        let Some(p) = mouse_location() else { continue };
        if p.y <= bar_bottom_y() {
            continue;
        }
        debug_log!("poll: cursor at y={} below bar; clearing hover", p.y);
        let (args, deferred) = s.apply_exit_all();
        let _ = tx.send(args);
        spawn_deferred_offs(&state, &tx, deferred);
    }
}

fn bind_socket() -> std::io::Result<UnixListener> {
    if let Err(e) = std::fs::remove_file(SOCKET_PATH) {
        if e.kind() != io::ErrorKind::NotFound {
            eprintln!("sketchybar-hoverd: removing stale socket {SOCKET_PATH}: {e}");
        }
    }
    // Restrict the initial socket mode atomically; otherwise there's a small
    // TOCTOU window between `bind` and the explicit `set_permissions(0o600)`
    // below where another local user could `connect()`. /tmp is world-
    // writable on macOS so this is the right level of paranoia.
    // SAFETY: umask(2) is async-signal-safe and the only side effect is
    // adjusting this process's mask, which we restore immediately after bind.
    let prev_umask = unsafe { umask(0o077) };
    let listener = UnixListener::bind(SOCKET_PATH);
    unsafe {
        umask(prev_umask);
    }
    let listener = listener?;
    let _ = std::fs::set_permissions(SOCKET_PATH, std::fs::Permissions::from_mode(0o600));
    Ok(listener)
}

fn main() -> std::io::Result<()> {
    // Any panic on any thread should crash the whole daemon so launchd
    // restarts it. Without this, a panic in (e.g.) the sketchybar worker
    // thread would silently leave the daemon "alive but useless" — the
    // accept loop keeps mutating state but no sketchybar calls fire,
    // and KeepAlive doesn't notice because the main thread is fine.
    std::panic::set_hook(Box::new(|info| {
        eprintln!(
            "sketchybar-hoverd: panic on thread {:?}: {info}",
            std::thread::current().name().unwrap_or("<unnamed>")
        );
        std::process::exit(1);
    }));

    let listener = bind_socket()?;

    let (name_to_target, target_keys) = item_configs();
    let state = Arc::new(Mutex::new(State {
        hovered_names: HashSet::new(),
        rendered_targets: HashSet::new(),
        target_on_at: HashMap::new(),
        pending_off_for: HashSet::new(),
        name_to_target,
        target_keys,
        name_gen: HashMap::new(),
    }));

    let (tx, rx) = mpsc::channel::<Vec<String>>();
    thread::spawn(move || sketchybar_worker(rx));

    {
        let state = Arc::clone(&state);
        let tx = tx.clone();
        thread::spawn(move || poll_loop(state, tx));
    }

    // Single-threaded accept loop: each client writes one line and exits,
    // so processing them in accept order guarantees we apply ENTER/EXIT in
    // the order the kernel queued the connections. State mutation is
    // microseconds and sketchybar invocations are dispatched to a dedicated
    // worker thread via `tx`, so the loop can keep up with fast sweeps.
    for conn in listener.incoming() {
        match conn {
            Ok(conn) => handle_client(Arc::clone(&state), tx.clone(), conn),
            Err(e) => eprintln!("sketchybar-hoverd: accept failed: {e}"),
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_state() -> State {
        let (name_to_target, target_keys) = item_configs();
        State {
            hovered_names: HashSet::new(),
            rendered_targets: HashSet::new(),
            target_on_at: HashMap::new(),
            pending_off_for: HashSet::new(),
            name_to_target,
            target_keys,
            name_gen: HashMap::new(),
        }
    }

    /// Pretend `target` was painted ON at `now - elapsed` so MIN_ON_DURATION
    /// gating decisions can be exercised deterministically.
    fn backdate_on(state: &mut State, target: &str, elapsed: Duration) {
        if let Some(ts) = state.target_on_at.get_mut(target) {
            *ts = Instant::now()
                .checked_sub(elapsed)
                .expect("test timestamp underflow");
        }
    }

    fn enter(state: &mut State, name: &str) -> (Vec<String>, Vec<DeferredOff>) {
        state.apply_enter(name.to_string())
    }

    /// Walk a `sketchybar` arg list and return the property strings that
    /// belong to the `--set <target>` group, or `None` if no such group is
    /// present. Skips anything before the first `--set <target>` and stops
    /// at the next `--set` or `--animate` boundary.
    fn props_for(args: &[String], target: &str) -> Option<Vec<String>> {
        let mut i = 0;
        while i + 1 < args.len() {
            if args[i] == "--set" && args[i + 1] == target {
                let mut props = Vec::new();
                let mut j = i + 2;
                while j < args.len() && args[j] != "--set" && args[j] != "--animate" {
                    props.push(args[j].clone());
                    j += 1;
                }
                return Some(props);
            }
            i += 1;
        }
        None
    }

    /// Single ENTER paints the target ON; subsequent EXIT (after enough
    /// elapsed time) paints it OFF.
    #[test]
    fn enter_then_exit_after_min_on() {
        let mut s = fresh_state();
        let (args, deferred) = enter(&mut s, "clock");
        assert!(!args.is_empty(), "ENTER should emit ON args");
        assert!(deferred.is_empty(), "no preempt → no defer");
        assert!(s.rendered_targets.contains("clock"));

        // Simulate EXIT after fade-in window has fully elapsed.
        backdate_on(&mut s, "clock", MIN_ON_DURATION + Duration::from_millis(10));
        let pending = s.snapshot_exit("clock").expect("snapshot");
        let (args, deferred) = s.try_apply_pending_removal(&pending.name, pending.generation);
        assert!(!args.is_empty(), "EXIT should emit OFF args");
        assert!(deferred.is_empty(), "fully elapsed → no defer");
        assert!(!s.rendered_targets.contains("clock"));
    }

    /// ENTER on a different target while the previous target is still inside
    /// MIN_ON_DURATION defers the OFF instead of issuing it immediately, so
    /// the preempted target's fade-in completes first.
    #[test]
    fn cross_target_preempt_defers_off() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        let (args, deferred) = enter(&mut s, "battery");

        // The new target is painted on, with the right key.
        let battery_props = props_for(&args, "battery").expect("battery --set group");
        assert_eq!(
            battery_props,
            vec!["label.background.color=0x33ffffff".to_string()]
        );
        // The preempted target gets neither an ON nor an OFF (deferred).
        assert!(
            props_for(&args, "clock").is_none(),
            "clock should not be painted in this batch (deferred)"
        );

        assert_eq!(deferred.len(), 1);
        assert_eq!(deferred[0].target, "clock");
        assert!(s.rendered_targets.contains("clock"));
        assert!(s.rendered_targets.contains("battery"));
        assert!(s.pending_off_for.contains("clock"));
    }

    /// Same-target names (label + icon) coexist in `hovered_names`; crossing
    /// between them must not add OFF args, and must not schedule a defer.
    #[test]
    fn same_target_names_dont_flicker() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        let rendered_before = s.rendered_targets.clone();
        let (args, deferred) = enter(&mut s, "clock_icon");
        assert!(args.is_empty(), "same target → no sketchybar args");
        assert!(deferred.is_empty(), "same target → no defer");
        assert_eq!(s.rendered_targets, rendered_before);
        assert!(s.hovered_names.contains("clock"));
        assert!(s.hovered_names.contains("clock_icon"));
    }

    /// A debounced EXIT scheduled before a fresh ENTER for the same name
    /// must no-op when it wakes (gen mismatch).
    #[test]
    fn debounced_exit_canceled_by_reenter() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        let pending = s.snapshot_exit("clock").expect("snapshot");
        // User comes back before the debounce fires.
        enter(&mut s, "clock");
        let (args, deferred) = s.try_apply_pending_removal(&pending.name, pending.generation);
        assert!(args.is_empty(), "stale gen → no args");
        assert!(deferred.is_empty());
        assert!(s.rendered_targets.contains("clock"));
    }

    /// Preempting drops other-target names AND bumps their gen, so any in-
    /// flight debounced EXIT for those names sees a stale gen on wake.
    #[test]
    fn preempt_invalidates_other_target_debounce() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        // Schedule a debounce for clock as if mouse.exited fired.
        let pending = s.snapshot_exit("clock").expect("snapshot");
        // Different-target ENTER preempts and bumps clock's gen.
        enter(&mut s, "battery");
        // The pending removal must now find a stale gen.
        let (args, deferred) = s.try_apply_pending_removal(&pending.name, pending.generation);
        assert!(args.is_empty(), "preempt-bumped gen invalidates debounce");
        assert!(deferred.is_empty());
    }

    /// A deferred OFF skips when the target has been re-hovered before its
    /// timer fires, but still clears the pending-off flag so future
    /// preempts can schedule fresh defers.
    #[test]
    fn deferred_off_skipped_on_rehover_clears_flag() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        enter(&mut s, "battery"); // schedules deferred-off for clock
        assert!(s.pending_off_for.contains("clock"));
        // User comes back before the defer fires.
        enter(&mut s, "clock");
        let args = s.try_apply_deferred_off("clock");
        assert!(args.is_empty(), "still hovered → skip");
        assert!(
            !s.pending_off_for.contains("clock"),
            "flag cleared so future preempts can re-schedule"
        );
        assert!(s.rendered_targets.contains("clock"));
    }

    /// `try_apply_deferred_off` must clear `pending_off_for` even when the
    /// target is no longer rendered (e.g. an EXIT_ALL or a sibling defer
    /// already cleared it). Otherwise the flag would prevent any future
    /// defer for that target.
    #[test]
    fn deferred_off_clears_flag_when_already_off() {
        let mut s = fresh_state();
        // Simulate an in-flight defer for a target that's already been
        // cleared by some other code path.
        s.pending_off_for.insert("clock".to_string());
        let args = s.try_apply_deferred_off("clock");
        assert!(args.is_empty());
        assert!(
            !s.pending_off_for.contains("clock"),
            "flag must clear so future preempts can re-schedule"
        );
    }

    /// Reconcile shouldn't schedule a duplicate defer for a target that
    /// already has one pending.
    #[test]
    fn duplicate_defer_not_scheduled() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        let (_, deferred1) = enter(&mut s, "battery");
        assert_eq!(deferred1.len(), 1);
        // Second preempt that would also defer the same target.
        let (_, deferred2) = enter(&mut s, "volume");
        // battery preempted now (recently entered), but clock is still
        // pending its earlier defer — so only battery is newly scheduled.
        assert!(deferred2.iter().all(|d| d.target != "clock"));
    }

    /// EXIT_ALL emits OFF args for every old-enough target and defers the
    /// rest. Final state has hovered_names empty.
    #[test]
    fn exit_all_clears_hovered_names() {
        let mut s = fresh_state();
        enter(&mut s, "clock");
        backdate_on(&mut s, "clock", MIN_ON_DURATION + Duration::from_millis(10));
        let (args, deferred) = s.apply_exit_all();
        assert!(s.hovered_names.is_empty());
        assert!(!args.is_empty(), "elapsed → OFF emitted");
        assert!(deferred.is_empty());
        assert!(!s.rendered_targets.contains("clock"));
    }

    /// Unknown subscribed names are ignored entirely.
    #[test]
    fn unknown_name_is_ignored() {
        let mut s = fresh_state();
        let (args, deferred) = enter(&mut s, "not_an_item");
        assert!(args.is_empty());
        assert!(deferred.is_empty());
        assert!(s.hovered_names.is_empty());
    }
}
