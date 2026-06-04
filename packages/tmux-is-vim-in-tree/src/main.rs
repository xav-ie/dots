//! Decide whether an nvim (or fzf, view, ...) is running anywhere in the
//! process subtree owned by a tmux pane's tty.
//!
//! vim-tmux-navigator's default `is_vim` check is `ps -t <pane_tty>` plus a
//! regex on `comm`. atuin hex (see ../../home-manager/modules/atuin) owns each
//! pane's tty and runs nu (and therefore nvim) on an *inner* pty, so the
//! default check only ever sees `atuin` and tmux falls through to select-pane,
//! making Ctrl+H/J/K/L skip vim splits entirely.
//!
//! We replicate the navigator's BFS-past-atuin, but read the whole process
//! table in a single pass (one `proc_listpids` syscall on macOS, one `/proc`
//! scan on Linux) and walk it in memory. The bash port spawned `ps`/`pgrep`
//! once per BFS level and was too slow to run on every keypress.
//!
//! Usage: `tmux-is-vim-in-tree <pane_tty>` (e.g. `/dev/ttys003`).
//! Exit 0 if a vim-like process is found in the subtree, 1 otherwise.

use std::collections::{HashMap, HashSet};
use std::os::unix::fs::MetadataExt;

struct Proc {
    pid: i32,
    ppid: i32,
    comm: String,
    /// Raw controlling-tty device number, in whatever encoding the platform
    /// reports (macOS dev_t, or Linux `tty_nr`). Compared via `matches_tty`.
    dev: u64,
}

fn main() {
    let tty = match std::env::args().nth(1) {
        Some(t) => t,
        None => std::process::exit(1),
    };

    // st_rdev of the pane's tty device file; the root processes we look for are
    // those whose controlling terminal matches it.
    let target = match std::fs::metadata(&tty) {
        Ok(m) => m.rdev(),
        Err(_) => std::process::exit(1),
    };

    let mut procs = Vec::new();
    platform::collect(&mut procs);

    let by_pid: HashMap<i32, usize> = procs.iter().enumerate().map(|(i, p)| (p.pid, i)).collect();
    let mut children: HashMap<i32, Vec<i32>> = HashMap::new();
    for p in &procs {
        if p.ppid != p.pid {
            children.entry(p.ppid).or_default().push(p.pid);
        }
    }

    // Seed the BFS with every process whose controlling tty is the pane's tty,
    // then descend through children (past atuin/nu) looking for vim.
    let mut frontier: Vec<i32> = procs
        .iter()
        .filter(|p| matches_tty(p.dev, target))
        .map(|p| p.pid)
        .collect();
    let mut visited: HashSet<i32> = HashSet::new();

    while !frontier.is_empty() {
        for pid in std::mem::take(&mut frontier) {
            if !visited.insert(pid) {
                continue;
            }
            if let Some(&i) = by_pid.get(&pid) {
                if is_vim_comm(&procs[i].comm) {
                    std::process::exit(0);
                }
            }
            if let Some(ch) = children.get(&pid) {
                frontier.extend(ch.iter().copied());
            }
        }
    }

    std::process::exit(1);
}

/// Faithful port of vim-tmux-navigator's `comm` regex (case-insensitive):
/// `^(\S+/)?g?\.?(view|l?n?vim?x?|fzf)(diff)?(-wrapped)?$`
///
/// Matches e.g. nvim, vim, vi, view, gvim, `.nvim-wrapped` (Nix wrapper),
/// vimdiff, gvimdiff, fzf — but not grep, vifm, etc.
fn is_vim_comm(comm: &str) -> bool {
    let base = comm.rsplit('/').next().unwrap_or(comm);
    let lower = base.to_ascii_lowercase();
    let mut s = lower.as_str();
    // `g?\.?` — only the optional `g`/`.` prefixes can consume these bytes,
    // since no core token starts with them, so a greedy strip is correct.
    s = s.strip_prefix('g').unwrap_or(s);
    s = s.strip_prefix('.').unwrap_or(s);

    for len in core_lengths(s) {
        let mut tail = &s[len..];
        tail = tail.strip_prefix("diff").unwrap_or(tail);
        tail = tail.strip_prefix("-wrapped").unwrap_or(tail);
        if tail.is_empty() {
            return true;
        }
    }
    false
}

/// Prefix lengths at which a core token (`view` | `l?n?vim?x?` | `fzf`) matches
/// the start of `s`. Multiple lengths are possible because of the optional
/// `m`/`x` (vi, vix, vim, vimx).
fn core_lengths(s: &str) -> Vec<usize> {
    let mut out = Vec::new();
    let b = s.as_bytes();
    if s.starts_with("view") {
        out.push(4);
    }
    if s.starts_with("fzf") {
        out.push(3);
    }
    // l? n? v i m? x?
    let mut i = 0;
    if b.get(i) == Some(&b'l') {
        i += 1;
    }
    if b.get(i) == Some(&b'n') {
        i += 1;
    }
    if b.get(i) == Some(&b'v') && b.get(i + 1) == Some(&b'i') {
        i += 2; // consumed "vi"
        out.push(i);
        // x directly after vi
        if b.get(i) == Some(&b'x') {
            out.push(i + 1);
        }
        // m, then optional x
        if b.get(i) == Some(&b'm') {
            out.push(i + 1);
            if b.get(i + 1) == Some(&b'x') {
                out.push(i + 2);
            }
        }
    }
    out
}

/// Whether a process's controlling-tty device `dev` refers to the same tty as
/// the target `st_rdev`.
#[cfg(target_os = "macos")]
fn matches_tty(dev: u64, target: u64) -> bool {
    // macOS reports the raw dev_t in both places, so a direct compare works.
    dev != 0 && dev == target
}

#[cfg(target_os = "linux")]
fn matches_tty(dev: u64, target: u64) -> bool {
    // `tty_nr` from /proc/<pid>/stat uses the kernel's split encoding, while
    // st_rdev uses glibc's; decode both to (major, minor) before comparing.
    if dev == 0 {
        return false;
    }
    let t = dev as u32;
    let maj_k = ((t >> 8) & 0xfff) as u64;
    let min_k = ((t & 0xff) | ((t >> 12) & 0xfff00)) as u64;
    let maj_g = ((target >> 8) & 0xfff) | ((target >> 32) & !0xfffu64);
    let min_g = (target & 0xff) | ((target >> 12) & !0xffu64);
    maj_k == maj_g && min_k == min_g
}

#[cfg(target_os = "macos")]
mod platform {
    use std::os::raw::{c_int, c_void};

    const PROC_ALL_PIDS: u32 = 1;
    const PROC_PIDTBSDINFO: c_int = 3;

    // struct proc_bsdinfo from <sys/proc_info.h> (PROC_PIDTBSDINFO_SIZE = 136).
    #[repr(C)]
    #[derive(Clone, Copy)]
    struct ProcBsdInfo {
        pbi_flags: u32,
        pbi_status: u32,
        pbi_xstatus: u32,
        pbi_pid: u32,
        pbi_ppid: u32,
        pbi_uid: u32,
        pbi_gid: u32,
        pbi_ruid: u32,
        pbi_rgid: u32,
        pbi_svuid: u32,
        pbi_svgid: u32,
        pbi_reserved: u32,
        pbi_comm: [u8; 16], // MAXCOMLEN
        pbi_name: [u8; 32], // 2 * MAXCOMLEN
        pbi_nfiles: u32,
        pbi_pgid: u32,
        pbi_pjobc: u32,
        e_tdev: u32, // controlling tty device
        e_tpgid: u32,
        pbi_nice: i32,
        pbi_start_tvsec: u64,
        pbi_start_tvusec: u64,
    }

    extern "C" {
        fn proc_listpids(
            r#type: u32,
            typeinfo: u32,
            buffer: *mut c_void,
            buffersize: c_int,
        ) -> c_int;
        fn proc_pidinfo(
            pid: c_int,
            flavor: c_int,
            arg: u64,
            buffer: *mut c_void,
            buffersize: c_int,
        ) -> c_int;
    }

    pub fn collect(procs: &mut Vec<super::Proc>) {
        unsafe {
            let needed = proc_listpids(PROC_ALL_PIDS, 0, std::ptr::null_mut(), 0);
            if needed <= 0 {
                return;
            }
            // Pad for processes spawned between the sizing and the real call.
            let cap = needed as usize / std::mem::size_of::<c_int>() + 16;
            let mut pids = vec![0i32; cap];
            let got = proc_listpids(
                PROC_ALL_PIDS,
                0,
                pids.as_mut_ptr() as *mut c_void,
                (pids.len() * std::mem::size_of::<c_int>()) as c_int,
            );
            if got <= 0 {
                return;
            }
            let n = got as usize / std::mem::size_of::<c_int>();
            let sz = std::mem::size_of::<ProcBsdInfo>() as c_int;
            for &pid in &pids[..n.min(pids.len())] {
                if pid <= 0 {
                    continue;
                }
                let mut info: ProcBsdInfo = std::mem::zeroed();
                let r = proc_pidinfo(
                    pid,
                    PROC_PIDTBSDINFO,
                    0,
                    &mut info as *mut _ as *mut c_void,
                    sz,
                );
                if r != sz {
                    continue; // process gone, or insufficient permission
                }
                procs.push(super::Proc {
                    pid: info.pbi_pid as i32,
                    ppid: info.pbi_ppid as i32,
                    comm: cstr(&info.pbi_comm),
                    dev: info.e_tdev as u64,
                });
            }
        }
    }

    fn cstr(buf: &[u8]) -> String {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).into_owned()
    }
}

#[cfg(target_os = "linux")]
mod platform {
    pub fn collect(procs: &mut Vec<super::Proc>) {
        let dir = match std::fs::read_dir("/proc") {
            Ok(d) => d,
            Err(_) => return,
        };
        for entry in dir.flatten() {
            let name = entry.file_name();
            let pid: i32 = match name.to_string_lossy().parse() {
                Ok(p) => p,
                Err(_) => continue, // non-numeric /proc entry
            };
            let stat = match std::fs::read_to_string(format!("/proc/{pid}/stat")) {
                Ok(s) => s,
                Err(_) => continue, // process gone
            };
            if let Some(p) = parse_stat(pid, &stat) {
                procs.push(p);
            }
        }
    }

    // `pid (comm) state ppid pgrp session tty_nr ...` — comm may contain spaces
    // and parens, so split after the last ')'.
    fn parse_stat(pid: i32, s: &str) -> Option<super::Proc> {
        let open = s.find('(')?;
        let close = s.rfind(')')?;
        let comm = s[open + 1..close].to_string();
        let mut it = s[close + 1..].split_whitespace();
        let _state = it.next()?;
        let ppid: i32 = it.next()?.parse().ok()?;
        let _pgrp = it.next()?;
        let _session = it.next()?;
        let tty_nr: i64 = it.next()?.parse().ok()?;
        Some(super::Proc {
            pid,
            ppid,
            comm,
            dev: tty_nr as u32 as u64,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_vim_family() {
        for name in [
            "vim",
            "nvim",
            "vi",
            "view",
            "gvim",
            "gview",
            ".nvim-wrapped",
            "nvim-wrapped",
            "vimdiff",
            "gvimdiff",
            "fzf",
            "vimx",
            "/nix/store/abc/bin/nvim",
        ] {
            assert!(is_vim_comm(name), "{name} should match");
        }
    }

    #[test]
    fn rejects_non_vim() {
        for name in ["grep", "git", "vifm", "atuin", "nu", "bash", "tmux", ""] {
            assert!(!is_vim_comm(name), "{name} should not match");
        }
    }
}
