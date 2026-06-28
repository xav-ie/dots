// move-pip — Picture-in-Picture mover hotkey client (native, fast-spawning).
//
// skhd spawns this once per key-repeat (~60/s while holding grow/shrink), so it
// must be cheap to launch. The Firefox fast path is done natively here over a
// UDP datagram: send the anchor to the firefox.cfg listener (ports 47100-47103)
// and, if a Firefox instance replies "ok", we're done. Only when no Firefox
// claims the PiP do we fall back to the Chromium/iPhone-Mirroring AX path, which
// (necessarily) shells out to osascript.
//
// UDP, not TCP: at ~60 connections/s a TCP client leaves hundreds of sockets in
// TIME_WAIT during a sustained hold, which chokes the network stack and makes
// the animation progressively janky. UDP is connectionless — nothing lingers.
//
// JS_PATH is baked at build time (default.nix `substitute --subst-var-by`).

use std::net::UdpSocket;
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::time::{Duration, Instant};

const PORTS: [u16; 4] = [47100, 47101, 47102, 47103];
const JS_PATH: &str = "@JS_PATH@";
const REPLY_WAIT: Duration = Duration::from_millis(35);

/// Send the anchor to each listener port and wait briefly for an "ok" reply.
/// Returns true if some Firefox instance handled the PiP.
fn query(ports: &[u16], anchor: &str) -> bool {
    let sock = match UdpSocket::bind("127.0.0.1:0") {
        Ok(s) => s,
        Err(_) => return false,
    };
    let msg = format!("{anchor}\n");
    let mut sent = false;
    for &p in ports {
        if sock.send_to(msg.as_bytes(), ("127.0.0.1", p)).is_ok() {
            sent = true;
        }
    }
    if !sent {
        return false;
    }
    // Collect replies until one says "ok" or the (bounded) wait elapses. A
    // "nopip"/"err" just means that instance didn't have the PiP — keep waiting
    // for another instance, but never longer than REPLY_WAIT total.
    let deadline = Instant::now() + REPLY_WAIT;
    let mut buf = [0u8; 16];
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() || sock.set_read_timeout(Some(remaining)).is_err() {
            return false;
        }
        match sock.recv_from(&mut buf) {
            Ok((n, _)) => {
                if n >= 2 && &buf[..2] == b"ok" {
                    return true;
                }
            }
            Err(_) => return false, // timed out, no "ok"
        }
    }
}

fn main() {
    let anchor = match std::env::args().nth(1) {
        Some(a) => a,
        None => std::process::exit(1),
    };

    // Firefox: whichever instance holds the PiP replies "ok"; then we stop.
    if query(&PORTS, &anchor) {
        return;
    }

    // No Firefox claimed it: Chromium/Chrome + iPhone Mirroring via Accessibility.
    let _ = Command::new("/usr/bin/osascript")
        .args(["-l", "JavaScript", JS_PATH, &anchor])
        .exec(); // replaces this process; only returns on failure
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket;
    use std::thread;

    /// One-shot UDP responder: receives one datagram, optionally replies to the
    /// sender, and yields the payload it got (so tests can assert the wire form).
    fn fake_listener(reply: Option<&'static str>) -> (u16, thread::JoinHandle<String>) {
        let sock = UdpSocket::bind("127.0.0.1:0").expect("bind");
        let port = sock.local_addr().unwrap().port();
        let handle = thread::spawn(move || {
            let mut buf = [0u8; 64];
            let (n, src) = sock.recv_from(&mut buf).expect("recv");
            if let Some(r) = reply {
                let _ = sock.send_to(r.as_bytes(), src);
            }
            String::from_utf8_lossy(&buf[..n]).into_owned()
        });
        (port, handle)
    }

    #[test]
    fn handled_when_reply_ok() {
        let (port, h) = fake_listener(Some("ok\n"));
        assert!(query(&[port], "grow"));
        assert_eq!(h.join().unwrap(), "grow\n"); // anchor + newline on the wire
    }

    #[test]
    fn not_handled_on_nopip() {
        let (port, h) = fake_listener(Some("nopip\n"));
        assert!(!query(&[port], "shrink"));
        assert_eq!(h.join().unwrap(), "shrink\n");
    }

    #[test]
    fn not_handled_on_err_reply() {
        let (port, h) = fake_listener(Some("err\n"));
        assert!(!query(&[port], "top-left"));
        let _ = h.join();
    }

    #[test]
    fn not_handled_when_no_reply() {
        let (port, h) = fake_listener(None);
        assert!(!query(&[port], "grow"));
        let _ = h.join();
    }

    #[test]
    fn not_handled_when_no_listener() {
        // Bind to grab a free port, then release it so nothing is listening.
        let s = UdpSocket::bind("127.0.0.1:0").unwrap();
        let port = s.local_addr().unwrap().port();
        drop(s);
        assert!(!query(&[port], "grow")); // times out within REPLY_WAIT
    }

    #[test]
    fn ok_is_matched_as_a_two_byte_prefix() {
        let (port, _h) = fake_listener(Some("ok\n"));
        assert!(query(&[port], "middle-middle"));
    }
}
