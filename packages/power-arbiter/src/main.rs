//! power-arbiter — demand-driven CPU/GPU power state for praesidium.
//!
//! Merges the two former Nushell daemons (the poll-loop arbiter and the
//! traefik-access-log tailer) into one small std-only binary so the idle
//! footprint is a couple MB instead of ~47 MB of resident nushell.
//!
//! Two jobs, one process, one thread:
//!   * watch traefik's JSON access log for inbound requests to allowlisted
//!     hosts (the HTTP demand source) — pseudo-event-driven via a 1 s tail poll
//!     of the file's new bytes, no `tail` subprocess; and
//!   * every EVAL_INTERVAL seconds (or immediately when an HTTP request needs a
//!     wake) recompute `active = ssh OR seat OR http` and drive the
//!     power-save-enter / power-save-exit systemd units to match.
//!
//! It also bookkeeps *what drives it*: every transition is appended to
//! HISTORY (jsonl, persisted under /var/lib) with its cause and trigger, a live
//! snapshot + running tallies are kept in STATE (json, under /run), and the
//! `status` subcommand renders all of that for a human.
//!
//! Config via env (set by the systemd unit):
//!   WAKE_HOSTS              csv of Host() names whose requests count as demand
//!   ACCESS_LOG              traefik access log path (default /var/lib/traefik/access.log)
//!   HTTP_COOLDOWN_SECONDS   stay awake this long after the last request (default 600)
//!   EVAL_INTERVAL_SECONDS   decision cadence (default 15)
//!   POLL_INTERVAL_MS        access-log tail cadence (default 1000)

use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::process::Command;
use std::thread::sleep;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const RUN_DIR: &str = "/run/power-arbiter";
const SEAT_IDLE: &str = "/run/power-arbiter/seat-idle";
const STATE: &str = "/run/power-arbiter/state.json";
const BY_HOST: &str = "/run/power-arbiter/http-by-host.tsv";
const HISTORY: &str = "/var/lib/power-arbiter/history.jsonl";
// Manual override: when this file holds "idle" or "active", it overrides the
// computed demand. The daemon picks up changes within one poll (~1s). It lives
// in the 0777 /run dir so `save`/`wake`/`auto` need no root.
const OVERRIDE: &str = "/run/power-arbiter/override";

const ENTER_UNIT: &str = "power-save-enter.service";
const EXIT_UNIT: &str = "power-save-exit.service";

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(default)
}

/// Pull a flat `"key":value` field out of a one-line JSON object. Handles the
/// only shapes we produce/consume: a quoted string, or a bare number/bool.
/// Sufficient because our own state/history lines are flat, and a traefik
/// RequestHost is a plain hostname with no embedded quotes.
fn jget<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let needle = format!("\"{key}\":");
    let start = line.find(&needle)? + needle.len();
    let rest = line[start..].trim_start();
    if let Some(rest) = rest.strip_prefix('"') {
        let end = rest.find('"')?;
        Some(&rest[..end])
    } else {
        let end = rest.find([',', '}']).unwrap_or(rest.len());
        Some(rest[..end].trim())
    }
}

fn fmt_dur(mut s: u64) -> String {
    let h = s / 3600;
    s %= 3600;
    let m = s / 60;
    s %= 60;
    if h > 0 {
        format!("{h}h{m}m")
    } else if m > 0 {
        format!("{m}m{s}s")
    } else {
        format!("{s}s")
    }
}

fn fmt_ago(at: u64) -> String {
    if at == 0 {
        return "never".into();
    }
    let n = now();
    if n < at {
        return "just now".into();
    }
    format!("{} ago", fmt_dur(n - at))
}

// ---------------------------------------------------------------------------
// Persisted state — a flat snapshot the daemon rewrites each eval and the
// `status` subcommand reads back. http-by-host counts live in a sidecar TSV.
// ---------------------------------------------------------------------------

#[derive(Default)]
struct Stats {
    state: String, // "active" | "idle" | ""
    since: u64,    // when we entered `state`
    ssh: bool,
    seat: bool,
    http: bool,
    last_http_host: String,
    last_http_at: u64,
    cooldown: u64,
    active_s: u64,
    idle_s: u64,
    transitions: u64,
    http_wakes: u64,
    over: String, // active manual override: "idle" | "active" | ""
    by_host: BTreeMap<String, u64>,
}

impl Stats {
    fn load() -> Stats {
        let mut s = Stats::default();
        if let Ok(txt) = fs::read_to_string(STATE) {
            let g = |k| jget(&txt, k).map(str::to_string);
            let n = |k| jget(&txt, k).and_then(|v| v.parse().ok()).unwrap_or(0);
            let b = |k| jget(&txt, k) == Some("true");
            s.state = g("state").unwrap_or_default();
            s.since = n("since");
            s.last_http_host = g("last_http_host").unwrap_or_default();
            s.last_http_at = n("last_http_at");
            s.active_s = n("active_s");
            s.idle_s = n("idle_s");
            s.transitions = n("transitions");
            s.http_wakes = n("http_wakes");
            s.over = g("over").unwrap_or_default();
            s.ssh = b("ssh");
            s.seat = b("seat");
            s.http = b("http");
        }
        if let Ok(txt) = fs::read_to_string(BY_HOST) {
            for line in txt.lines() {
                if let Some((host, c)) = line.split_once('\t') {
                    if let Ok(c) = c.trim().parse() {
                        s.by_host.insert(host.to_string(), c);
                    }
                }
            }
        }
        s
    }

    fn save(&self) {
        let json = format!(
            concat!(
                "{{\"state\":\"{}\",\"since\":{},\"ssh\":{},\"seat\":{},\"http\":{},",
                "\"last_http_host\":\"{}\",\"last_http_at\":{},\"cooldown\":{},",
                "\"active_s\":{},\"idle_s\":{},\"transitions\":{},\"http_wakes\":{},",
                "\"over\":\"{}\",\"updated\":{}}}\n"
            ),
            self.state,
            self.since,
            self.ssh,
            self.seat,
            self.http,
            self.last_http_host,
            self.last_http_at,
            self.cooldown,
            self.active_s,
            self.idle_s,
            self.transitions,
            self.http_wakes,
            self.over,
            now(),
        );
        let _ = write_atomic(STATE, &json);

        let mut tsv = String::new();
        for (h, c) in &self.by_host {
            tsv.push_str(&format!("{h}\t{c}\n"));
        }
        let _ = write_atomic(BY_HOST, &tsv);
    }
}

fn write_atomic(path: &str, contents: &str) -> std::io::Result<()> {
    let tmp = format!("{path}.tmp");
    fs::write(&tmp, contents)?;
    fs::rename(&tmp, path)
}

/// Append one transition to the persistent history log.
fn record(from: &str, to: &str, cause: &str, trigger: &str) {
    if let Some(dir) = Path::new(HISTORY).parent() {
        let _ = fs::create_dir_all(dir);
    }
    let line = format!(
        "{{\"at\":{},\"from\":\"{}\",\"to\":\"{}\",\"cause\":\"{}\",\"trigger\":\"{}\"}}\n",
        now(),
        from,
        to,
        cause,
        trigger
    );
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(HISTORY) {
        let _ = f.write_all(line.as_bytes());
    }
}

// ---------------------------------------------------------------------------
// Demand sources
// ---------------------------------------------------------------------------

/// Any SSH session present. Shells out to the repo's `is-sshed` (on PATH via the
/// unit's `path`), which checks utmp for a pts login.
fn ssh_demand() -> bool {
    Command::new("is-sshed")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "true")
        .unwrap_or(false)
}

/// Seat is demand unless hypridle has dropped the idle stamp.
fn seat_demand() -> bool {
    !Path::new(SEAT_IDLE).exists()
}

// ---------------------------------------------------------------------------
// Access-log tail — read whatever bytes appended since last time, split into
// complete lines (carrying any partial trailing line forward), tolerate the
// file being absent / rotated / truncated.
// ---------------------------------------------------------------------------

struct Tail {
    path: String,
    pos: u64,
    carry: String,
}

impl Tail {
    fn new(path: String) -> Tail {
        // Start at EOF so we react only to *new* requests, not replay history.
        let pos = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        Tail {
            path,
            pos,
            carry: String::new(),
        }
    }

    fn poll(&mut self) -> Vec<String> {
        let len = match fs::metadata(&self.path) {
            Ok(m) => m.len(),
            Err(_) => return Vec::new(), // not created yet
        };
        if len < self.pos {
            // Truncated or rotated — restart from the top of the new file.
            self.pos = 0;
            self.carry.clear();
        }
        if len == self.pos {
            return Vec::new();
        }
        let mut f = match File::open(&self.path) {
            Ok(f) => f,
            Err(_) => return Vec::new(),
        };
        if f.seek(SeekFrom::Start(self.pos)).is_err() {
            return Vec::new();
        }
        let mut buf = String::new();
        if f.read_to_string(&mut buf).is_err() {
            return Vec::new();
        }
        self.pos = len;

        let mut data = std::mem::take(&mut self.carry);
        data.push_str(&buf);
        let mut lines: Vec<String> = data.split('\n').map(str::to_string).collect();
        // The last element is the (possibly empty) partial line — carry it.
        self.carry = lines.pop().unwrap_or_default();
        lines.into_iter().filter(|l| !l.is_empty()).collect()
    }
}

// ---------------------------------------------------------------------------
// Actuator — ask the (idempotent) systemd oneshots to flip the hardware.
// ---------------------------------------------------------------------------

fn apply(active: bool) {
    let unit = if active { EXIT_UNIT } else { ENTER_UNIT };
    let _ = Command::new("systemctl").arg("start").arg(unit).status();
}

// ---------------------------------------------------------------------------
// Manual override (save / wake / auto subcommands)
// ---------------------------------------------------------------------------

/// The active override, if the file holds a valid value.
fn read_override() -> Option<String> {
    fs::read_to_string(OVERRIDE)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| s == "idle" || s == "active")
}

/// Write/clear the override file. The running daemon reacts within ~1s.
fn set_override(mode: &str) {
    let _ = fs::create_dir_all(RUN_DIR);
    match mode {
        "idle" | "save" => {
            let _ = fs::write(OVERRIDE, "idle\n");
            println!("power-arbiter: forced IDLE (power save) — `power-arbiter auto` to resume.");
        }
        "active" | "wake" => {
            let _ = fs::write(OVERRIDE, "active\n");
            println!(
                "power-arbiter: forced ACTIVE (pinned full speed) — `power-arbiter auto` to resume."
            );
        }
        "auto" | "clear" | "resume" => {
            let _ = fs::remove_file(OVERRIDE);
            println!("power-arbiter: override cleared; resuming demand-driven control.");
        }
        _ => {
            eprintln!("power-arbiter: unknown force mode {mode:?}; expected idle|active|auto");
            std::process::exit(2);
        }
    }
}

fn print_help() {
    print!(
        "\
power-arbiter — demand-driven CPU/GPU power save (ssh / seat / http)

USAGE:
    power-arbiter [SUBCOMMAND]

SUBCOMMANDS:
    status         Show current state, demand sources, tallies, recent transitions
    save           Force IDLE now (drop to power save), ignoring demand
    wake           Force ACTIVE now (pin full speed), ignoring demand
    auto           Clear a manual override; resume demand-driven control
    force <mode>   Same as save/wake/auto (mode = idle | active | auto)
    daemon         Run the reconcile loop (invoked by the systemd unit)
    help, --help   Show this help

The override is a file at /run/power-arbiter/override that the running daemon
picks up within ~1s; save/wake/auto need no root.
"
    );
}

// ---------------------------------------------------------------------------
// status subcommand
// ---------------------------------------------------------------------------

fn print_status() {
    let s = Stats::load();
    if s.state.is_empty() {
        println!("power-arbiter: not running yet (no state at {STATE})");
        return;
    }
    let in_state = fmt_dur(now().saturating_sub(s.since));
    println!("power-arbiter: {} for {}", s.state.to_uppercase(), in_state);
    if !s.over.is_empty() {
        println!(
            "  override: forced {} (manual) — `power-arbiter auto` to resume",
            s.over.to_uppercase()
        );
    }
    println!(
        "  demand: ssh={}  seat={}  http={}",
        yn(s.ssh, "yes", "no"),
        yn(s.seat, "in-use", "idle"),
        yn(s.http, "recent", "no"),
    );
    if s.last_http_at > 0 {
        println!(
            "  last http wake: {} ({})",
            s.last_http_host,
            fmt_ago(s.last_http_at)
        );
    }
    let total = s.active_s + s.idle_s;
    let pct = if total > 0 {
        s.active_s * 100 / total
    } else {
        0
    };
    println!(
        "  since start: active {} / idle {} ({pct}% active), {} transitions, {} http wakes",
        fmt_dur(s.active_s),
        fmt_dur(s.idle_s),
        s.transitions,
        s.http_wakes,
    );
    if !s.by_host.is_empty() {
        let mut hosts: Vec<_> = s.by_host.iter().collect();
        hosts.sort_by(|a, b| b.1.cmp(a.1));
        let parts: Vec<String> = hosts.iter().map(|(h, c)| format!("{h} {c}")).collect();
        println!("  http wakes by host: {}", parts.join(", "));
    }

    // Recent transitions from the persistent history log.
    if let Ok(txt) = fs::read_to_string(HISTORY) {
        let lines: Vec<&str> = txt.lines().filter(|l| !l.is_empty()).collect();
        let tail = &lines[lines.len().saturating_sub(8)..];
        if !tail.is_empty() {
            println!("  recent transitions:");
            for l in tail {
                let at: u64 = jget(l, "at").and_then(|v| v.parse().ok()).unwrap_or(0);
                let from = jget(l, "from").unwrap_or("?");
                let to = jget(l, "to").unwrap_or("?");
                let cause = jget(l, "cause").unwrap_or("");
                println!("    {:>10}  {} -> {}  ({})", fmt_ago(at), from, to, cause);
            }
        }
    }
}

fn yn(b: bool, t: &str, f: &str) -> String {
    if b { t.into() } else { f.into() }
}

// ---------------------------------------------------------------------------
// daemon
// ---------------------------------------------------------------------------

fn run_daemon() {
    let _ = fs::create_dir_all(RUN_DIR);
    if let Some(dir) = Path::new(HISTORY).parent() {
        let _ = fs::create_dir_all(dir);
    }

    let cooldown = env_u64("HTTP_COOLDOWN_SECONDS", 600);
    let eval_interval = env_u64("EVAL_INTERVAL_SECONDS", 15);
    let poll_ms = env_u64("POLL_INTERVAL_MS", 1000);
    let access_log =
        std::env::var("ACCESS_LOG").unwrap_or_else(|_| "/var/lib/traefik/access.log".into());
    let wake_hosts: Vec<String> = std::env::var("WAKE_HOSTS")
        .unwrap_or_default()
        .split(',')
        .map(|h| h.trim().to_string())
        .filter(|h| !h.is_empty())
        .collect();

    println!(
        "power-arbiter: cooldown={cooldown}s eval={eval_interval}s log={access_log} hosts={:?}",
        wake_hosts
    );

    let mut s = Stats::load();
    s.cooldown = cooldown;

    let mut tail = Tail::new(access_log);
    let mut last_override = read_override();
    let mut last_eval = 0u64;
    let mut last_accrual = now();
    let mut first = true;

    loop {
        let t = now();

        // --- HTTP demand: scan whatever the access log appended. ---
        let mut wake_trigger: Option<String> = None;
        for line in tail.poll() {
            let host =
                jget(&line, "RequestHost").map(|h| h.split(':').next().unwrap_or(h).to_string());
            if let Some(host) = host {
                if wake_hosts.iter().any(|h| h == &host) {
                    s.last_http_host = host.clone();
                    s.last_http_at = t;
                    s.http_wakes += 1;
                    *s.by_host.entry(host.clone()).or_insert(0) += 1;
                    // Only force an immediate eval if we actually need to wake;
                    // once active, further requests just refresh the cooldown.
                    if s.state != "active" {
                        wake_trigger = Some(format!("http:{host}"));
                    }
                }
            }
        }

        // --- Manual override: react within one poll when it changes. ---
        let over = read_override();
        let override_changed = over != last_override;
        if override_changed {
            last_override = over.clone();
        }

        // --- Decision: every eval_interval, on a wake, or on override change. ---
        if first
            || wake_trigger.is_some()
            || override_changed
            || t.saturating_sub(last_eval) >= eval_interval
        {
            // Accrue elapsed time to the state we were in before deciding.
            let delta = t.saturating_sub(last_accrual);
            match s.state.as_str() {
                "active" => s.active_s += delta,
                "idle" => s.idle_s += delta,
                _ => {}
            }
            last_accrual = t;

            s.ssh = ssh_demand();
            s.seat = seat_demand();
            s.http = s.last_http_at != 0 && t.saturating_sub(s.last_http_at) < cooldown;
            s.over = over.clone().unwrap_or_default();
            let demand_active = s.ssh || s.seat || s.http;
            // A manual override (save/wake) wins over computed demand.
            let desired = match over.as_deref() {
                Some(o) => o,
                None if demand_active => "active",
                None => "idle",
            };

            // Always sync hardware on the first tick (state after a reboot/restart
            // is unknown); thereafter act only on change.
            if first {
                apply(desired == "active");
            }

            if s.state != desired {
                let cause = demand_cause(&s);
                let trigger = match over.as_deref() {
                    Some(o) => format!("manual:{o}"),
                    None => wake_trigger.clone().unwrap_or_else(|| {
                        if desired == "idle" {
                            "all-quiet".into()
                        } else {
                            cause.clone()
                        }
                    }),
                };
                let from = if s.state.is_empty() {
                    "unknown".to_string()
                } else {
                    s.state.clone()
                };
                println!(
                    "-> {desired} (ssh={} seat={} http={} over={:?}) trigger={trigger}",
                    s.ssh, s.seat, s.http, over
                );
                // Don't count the initial sync from "unknown" as a transition.
                if !s.state.is_empty() {
                    s.transitions += 1;
                }
                record(&from, desired, &cause, &trigger);
                if !first {
                    apply(desired == "active");
                }
                s.state = desired.to_string();
                s.since = t;
            }

            first = false;
            last_eval = t;
            s.save();
        }

        sleep(Duration::from_millis(poll_ms.max(50)));
    }
}

/// Human-readable list of which sources are currently holding demand.
fn demand_cause(s: &Stats) -> String {
    let mut v = Vec::new();
    if s.ssh {
        v.push("ssh");
    }
    if s.seat {
        v.push("seat");
    }
    if s.http {
        v.push("http");
    }
    if v.is_empty() {
        "none".into()
    } else {
        v.join("+")
    }
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("status") => print_status(),
        Some("daemon") | None => run_daemon(),
        Some("save") => set_override("idle"),
        Some("wake") => set_override("active"),
        Some("auto") | Some("resume") | Some("clear") => set_override("auto"),
        Some("force") => set_override(std::env::args().nth(2).as_deref().unwrap_or("")),
        Some("help") | Some("--help") | Some("-h") => print_help(),
        Some(other) => {
            eprintln!("power-arbiter: unknown subcommand {other:?}\n");
            print_help();
            std::process::exit(2);
        }
    }
}
