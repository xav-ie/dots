//! Tiny dispatcher that sketchybar invokes as `script=`.
//!
//! For mouse-related events (`mouse.entered`, `mouse.exited`,
//! `mouse.exited.global`) it forwards a single line to the daemon over a Unix
//! socket and exits — no Nushell startup, no fan-out triggers.
//!
//! For any other sender, if `--plugin <path>` was supplied it execs Nushell
//! against that plugin so the existing data-update logic (clock tick,
//! battery_change, front_app_switched, …) keeps working.

use std::env;
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::time::Duration;

use sketchybar_hover::{HoverEvent, SOCKET_PATH};

fn main() {
    let sender = env::var("SENDER").unwrap_or_default();
    let name = env::var("NAME").unwrap_or_default();

    let event = match sender.as_str() {
        "mouse.entered" => Some(HoverEvent::Enter(name)),
        "mouse.exited" => Some(HoverEvent::Exit(name)),
        "mouse.exited.global" => Some(HoverEvent::ExitAll),
        _ => None,
    };

    if let Some(event) = event {
        send(&event);
        return;
    }

    let mut args = env::args().skip(1);
    match (args.next().as_deref(), args.next()) {
        (Some("--plugin"), Some(plugin)) => {
            let err = Command::new("nu").arg("--stdin").arg(plugin).exec();
            eprintln!("sketchybar-hover: failed to exec nu: {err}");
            std::process::exit(127);
        }
        (Some("--plugin"), None) => {
            eprintln!("sketchybar-hover: --plugin requires a path argument");
            std::process::exit(2);
        }
        (None, _) => {
            eprintln!(
                "sketchybar-hover: non-mouse SENDER={sender:?} but no --plugin <path> argument"
            );
            std::process::exit(2);
        }
        (Some(other), _) => {
            eprintln!("sketchybar-hover: unexpected argument {other:?}");
            std::process::exit(2);
        }
    }
}

fn send(event: &HoverEvent) {
    let Ok(mut sock) = UnixStream::connect(SOCKET_PATH) else {
        // Daemon not up yet: fail silently so we don't spam the sketchybar log.
        return;
    };
    // Don't let a stuck daemon hang sketchybar's script slot.
    let _ = sock.set_write_timeout(Some(Duration::from_millis(100)));
    let _ = sock.write_all(event.serialize().as_bytes());
}
