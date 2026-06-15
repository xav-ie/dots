//! Human-in-the-loop takeover.
//!
//! When the agent hits a login wall it asks a human to drive the session's
//! active page directly — so credentials never pass through the agent. The
//! flow is split across two processes that share the state dir (exactly like
//! `logs`/`saved_states` share it):
//!
//!   1. The MCP `request_human_takeover` tool mints a random token and writes a
//!      ticket file (`tokens/<token>.json`) describing which CDP target the
//!      human should drive. It returns a URL and then `await_human_takeover`
//!      blocks on a sentinel (`done/<token>`).
//!   2. This daemon (`browser-session-takeover`, host-side systemd unit) serves
//!      the takeover page at that URL. The page's JavaScript opens a WebSocket
//!      straight to Chrome's DevTools endpoint (`CHROME_WS_BASE`), runs
//!      `Page.startScreencast`, renders frames to a canvas, and forwards the
//!      human's mouse/keyboard as `Input.dispatch*` commands. A "Done" button
//!      POSTs back here, which drops the sentinel and unblocks the agent.
//!
//! The daemon never touches Chrome itself — all CDP traffic is browser↔Chrome.
//! That keeps the heavy screencast/input logic in plain JS (see PAGE_TEMPLATE)
//! and the daemon a dependency-free tokio HTTP shim.
use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// What the human is being asked to drive. Written by the MCP tool, read by the
/// daemon when it serves the page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ticket {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    /// CDP targetId of the page to screencast. The WS path is
    /// `/devtools/page/<targetId>`.
    #[serde(rename = "targetId")]
    pub target_id: String,
    /// Unix-millis after which the daemon refuses to serve the page.
    #[serde(rename = "expiresAtMs")]
    pub expires_at_ms: u128,
}

/// Shared takeover dir under the state dir (`/var/lib/browser-session-mcp`).
/// Both the container MCP and the host daemon see the same path via the volume
/// mount, so file-based IPC works across the process boundary.
pub fn takeover_dir() -> PathBuf {
    std::env::var("TAKEOVER_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/lib/browser-session-mcp/takeover"))
}

/// Public, human-facing base URL of the takeover daemon (e.g. an SSH-tunnelled
/// `http://localhost:9223` or a Traefik `https://chrome-takeover.<base>`). The
/// MCP only embeds this string in its reply; it never connects to it.
pub fn base_url() -> Option<String> {
    std::env::var("TAKEOVER_BASE_URL")
        .ok()
        .filter(|s| !s.is_empty())
        .map(|s| s.trim_end_matches('/').to_string())
}

fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

/// Unix-millis `ttl_ms` from now — for stamping a ticket's expiry.
pub fn expiry_ms(ttl_ms: u64) -> u128 {
    now_ms() + ttl_ms as u128
}

/// 32 hex chars of OS randomness. Token is the only thing guarding the page, so
/// it must be unguessable when exposed beyond loopback.
pub fn mint_token() -> Result<String> {
    let mut buf = [0u8; 16];
    getrandom::getrandom(&mut buf).map_err(|e| anyhow!("getrandom: {e}"))?;
    Ok(buf.iter().map(|b| format!("{b:02x}")).collect())
}

fn tokens_dir() -> PathBuf {
    takeover_dir().join("tokens")
}
fn done_dir() -> PathBuf {
    takeover_dir().join("done")
}
fn ticket_path(token: &str) -> PathBuf {
    tokens_dir().join(format!("{token}.json"))
}
fn done_path(token: &str) -> PathBuf {
    done_dir().join(token)
}
fn claims_dir() -> PathBuf {
    takeover_dir().join("claims")
}
fn claim_path(token: &str) -> PathBuf {
    claims_dir().join(token)
}

/// First-come-first-serve claim. Atomically (`create_new`) record a per-browser
/// secret the first time a token's page is served; returns:
///   Ok(Some(secret))  — caller is the claimant (send it as a cookie)
///   Ok(None)          — already claimed by `presented` (a valid reload)
///   Err(_)            — already claimed by someone else (reject)
/// so a leaked URL is useless once the real user has opened it.
async fn claim(token: &str, presented: Option<&str>) -> std::io::Result<Option<String>> {
    use std::io::{Error, ErrorKind};
    let path = claim_path(token);
    // Fast path: already claimed — only the holder of the secret may proceed.
    if let Ok(existing) = tokio::fs::read_to_string(&path).await {
        let existing = existing.trim();
        // A zero-length claim file would be matched by an empty `tk_claim=`
        // cookie — never accept it as a valid claim.
        if existing.is_empty() {
            return Err(Error::new(ErrorKind::PermissionDenied, "claim file corrupt"));
        }
        return if presented == Some(existing) {
            Ok(None)
        } else {
            Err(Error::new(ErrorKind::PermissionDenied, "already claimed"))
        };
    }
    let secret = mint_token().map_err(|e| Error::new(ErrorKind::Other, e.to_string()))?;
    tokio::fs::create_dir_all(claims_dir()).await.ok();
    // Write the secret to a per-attempt temp file (named with the secret so two
    // concurrent first-claims never share a temp), then `hard_link` it into
    // place. hard_link is atomic and fails if the target exists, so the first
    // writer wins AND the claim file is never observed empty (unlike
    // create_new + a separate write).
    let tmp = claims_dir().join(format!("{token}-{secret}.tmp"));
    tokio::fs::write(&tmp, secret.as_bytes()).await?;
    let linked = tokio::fs::hard_link(&tmp, &path).await;
    let _ = tokio::fs::remove_file(&tmp).await;
    match linked {
        Ok(()) => Ok(Some(secret)),
        // Lost the race; whoever won holds it, and it isn't us.
        Err(e) if e.kind() == ErrorKind::AlreadyExists => {
            Err(Error::new(ErrorKind::PermissionDenied, "already claimed"))
        }
        Err(e) => Err(e),
    }
}

/// Check a presented cookie matches the recorded claim (for the Done POST).
/// A missing or empty claim file never matches.
async fn claim_matches(token: &str, presented: Option<&str>) -> bool {
    match tokio::fs::read_to_string(claim_path(token)).await {
        Ok(existing) => {
            let existing = existing.trim();
            !existing.is_empty() && presented == Some(existing)
        }
        Err(_) => false,
    }
}

/// Persist a ticket and return the token. Called by `request_human_takeover`.
pub async fn write_ticket(token: &str, ticket: &Ticket) -> Result<()> {
    tokio::fs::create_dir_all(tokens_dir())
        .await
        .context("creating tokens dir")?;
    let json = serde_json::to_vec_pretty(ticket).context("serializing ticket")?;
    // Write-then-rename so the daemon never reads a half-written ticket if the
    // human opens the URL within milliseconds of this call. Rename is atomic
    // within the same dir.
    let final_path = ticket_path(token);
    let tmp_path = tokens_dir().join(format!("{token}.json.tmp"));
    tokio::fs::write(&tmp_path, json)
        .await
        .context("writing ticket tmp")?;
    tokio::fs::rename(&tmp_path, &final_path)
        .await
        .context("renaming ticket into place")?;
    Ok(())
}

async fn read_ticket(token: &str) -> Result<Ticket> {
    let bytes = tokio::fs::read(ticket_path(token))
        .await
        .context("reading ticket")?;
    serde_json::from_slice(&bytes).context("parsing ticket")
}

/// Block until the human clicks Done (sentinel appears) or the timeout elapses.
/// Returns `true` if completed, `false` on timeout. Called by
/// `await_human_takeover`.
pub async fn wait_for_done(token: &str, timeout: Duration) -> bool {
    let deadline = tokio::time::Instant::now() + timeout;
    let path = done_path(token);
    loop {
        if tokio::fs::try_exists(&path).await.unwrap_or(false) {
            return true;
        }
        if tokio::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

/// Best-effort cleanup of a finished/abandoned takeover's files.
pub async fn cleanup(token: &str) {
    let _ = tokio::fs::remove_file(ticket_path(token)).await;
    let _ = tokio::fs::remove_file(done_path(token)).await;
    let _ = tokio::fs::remove_file(claim_path(token)).await;
}

/// Delete tickets past their expiry (with any matching done-sentinel) and stale
/// `.tmp` files. `await_human_takeover` only cleans up tickets it completes, so
/// timed-out/abandoned ones would otherwise accumulate. Best-effort.
async fn sweep_expired() {
    let Ok(mut entries) = tokio::fs::read_dir(tokens_dir()).await else {
        return;
    };
    let now = now_ms();
    while let Ok(Some(entry)) = entries.next_entry().await {
        let path = entry.path();
        let Some(name) = path.file_name().and_then(|s| s.to_str()) else {
            continue;
        };
        // Leftover temp file from an interrupted write — always junk.
        if name.ends_with(".tmp") {
            let _ = tokio::fs::remove_file(&path).await;
            continue;
        }
        let Some(token) = name.strip_suffix(".json") else {
            continue;
        };
        // Unparsable ticket → treat as junk and remove; valid + expired → remove.
        let expired = match tokio::fs::read(&path).await {
            Ok(bytes) => serde_json::from_slice::<Ticket>(&bytes)
                .map(|t| t.expires_at_ms <= now)
                .unwrap_or(true),
            Err(_) => continue,
        };
        if expired {
            let token = token.to_string();
            let _ = tokio::fs::remove_file(&path).await;
            let _ = tokio::fs::remove_file(done_path(&token)).await;
            let _ = tokio::fs::remove_file(claim_path(&token)).await;
        }
    }
}

// ---- daemon ---------------------------------------------------------------

/// Run the takeover HTTP daemon until killed. Env:
///   TAKEOVER_BIND     (default 127.0.0.1:9223) — where to listen
///   TAKEOVER_DIR      (default /var/lib/browser-session-mcp/takeover)
///   CHROME_WS_BASE    (required) — e.g. wss://chrome.lalala.casa
pub async fn run() -> Result<()> {
    let bind = std::env::var("TAKEOVER_BIND").unwrap_or_else(|_| "127.0.0.1:9223".to_string());
    let chrome_ws_base = std::env::var("CHROME_WS_BASE")
        .ok()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("CHROME_WS_BASE is required (e.g. wss://chrome.<base>)"))?;
    let chrome_ws_base = chrome_ws_base.trim_end_matches('/').to_string();

    tokio::fs::create_dir_all(tokens_dir()).await.ok();
    tokio::fs::create_dir_all(done_dir()).await.ok();
    tokio::fs::create_dir_all(claims_dir()).await.ok();

    let listener = TcpListener::bind(&bind)
        .await
        .with_context(|| format!("binding {bind}"))?;
    tracing::info!(%bind, "browser-session-takeover listening");

    // Periodically prune expired/abandoned tickets so the state dir stays bounded.
    tokio::spawn(async {
        loop {
            sweep_expired().await;
            tokio::time::sleep(Duration::from_secs(300)).await;
        }
    });

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(v) => v,
            Err(err) => {
                tracing::warn!(error = %err, "accept failed");
                continue;
            }
        };
        let base = chrome_ws_base.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_conn(stream, &base).await {
                tracing::debug!(error = %err, %peer, "connection error");
            }
        });
    }
}

/// Minimal HTTP/1.1: read the request line + headers, route, respond with
/// `Connection: close`. We serve at most a small HTML page and a 200, so a
/// single-shot handler is plenty — no keep-alive, no body streaming.
async fn handle_conn(mut stream: TcpStream, chrome_ws_base: &str) -> Result<()> {
    const MAX_HEADER: usize = 16 * 1024;
    let mut buf = Vec::with_capacity(2048);
    let mut tmp = [0u8; 1024];
    // Read until end-of-headers (CRLFCRLF). Requests here are tiny (no body we
    // read). Only scan the freshly-appended bytes (+3 overlap so a terminator
    // split across reads is still caught) rather than rescanning the whole
    // buffer each time.
    let mut headers_done = false;
    while buf.len() < MAX_HEADER {
        let n = stream.read(&mut tmp).await?;
        if n == 0 {
            break; // client closed before sending full headers
        }
        let scan_from = buf.len().saturating_sub(3);
        buf.extend_from_slice(&tmp[..n]);
        if buf[scan_from..].windows(4).any(|w| w == b"\r\n\r\n") {
            headers_done = true;
            break;
        }
    }

    let r = if !headers_done {
        // Never saw the header terminator (truncated or oversized) — refuse
        // rather than parse a partial request.
        Resp::new("400 Bad Request", "text/plain", "bad request")
    } else {
        // Parse ONLY the request line (first line), not the whole buffer, so a
        // later header line can never be mistaken for the method/path.
        let head = String::from_utf8_lossy(&buf);
        let request_line = head.lines().next().unwrap_or("");
        let mut parts = request_line.split_whitespace();
        let method = parts.next().unwrap_or("");
        let path = parts.next().unwrap_or("/");
        let cookie = extract_cookie(&head, "tk_claim");
        route(method, path, chrome_ws_base, cookie.as_deref()).await
    };
    let set_cookie = match &r.set_cookie {
        Some(c) => format!("Set-Cookie: {c}\r\n"),
        None => String::new(),
    };
    let resp = format!(
        "HTTP/1.1 {}\r\nContent-Type: {}\r\nContent-Length: {}\r\n{set_cookie}Connection: close\r\nCache-Control: no-store\r\n\r\n",
        r.status,
        r.ctype,
        r.body.len(),
    );
    stream.write_all(resp.as_bytes()).await?;
    stream.write_all(r.body.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

/// One HTTP response: status line + content + an optional `Set-Cookie`.
struct Resp {
    status: &'static str,
    ctype: &'static str,
    body: String,
    set_cookie: Option<String>,
}

impl Resp {
    fn new(status: &'static str, ctype: &'static str, body: impl Into<String>) -> Self {
        Self {
            status,
            ctype,
            body: body.into(),
            set_cookie: None,
        }
    }
    fn cookie(mut self, c: String) -> Self {
        self.set_cookie = Some(c);
        self
    }
}

/// Pull a single cookie value out of the request headers (case-insensitive
/// header name, first match). Returns the raw value of `name=...`.
fn extract_cookie(head: &str, name: &str) -> Option<String> {
    let line = head
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("cookie:"))?;
    let value = line.splitn(2, ':').nth(1)?;
    let prefix = format!("{name}=");
    value
        .split(';')
        .map(str::trim)
        .find_map(|pair| pair.strip_prefix(&prefix))
        .map(str::to_string)
}

async fn route(method: &str, path: &str, chrome_ws_base: &str, cookie: Option<&str>) -> Resp {
    // Strip a query string if any.
    let path = path.split('?').next().unwrap_or(path);

    if method == "GET" && path == "/healthz" {
        return Resp::new("200 OK", "text/plain", "ok");
    }

    if method == "POST" {
        if let Some(rest) = path.strip_prefix("/takeover/") {
            // POST /takeover/<token>/claim — the real browser claims here, on
            // page load. Unfurl bots / prefetchers issue GETs and don't run JS,
            // so they never reach this and never learn the targetId.
            if let Some(token) = rest.strip_suffix("/claim") {
                return claim_response(token, chrome_ws_base, cookie).await;
            }
            // POST /takeover/<token>/done — only the claimant (matching cookie).
            if let Some(token) = rest.strip_suffix("/done") {
                if !valid_token(token) {
                    return Resp::new("400 Bad Request", "text/plain", "bad token");
                }
                if !claim_matches(token, cookie).await {
                    return Resp::new("403 Forbidden", "text/plain", "not the claimant");
                }
                if let Err(err) = mark_done(token).await {
                    tracing::warn!(error = %err, "marking done failed");
                    return Resp::new("500 Internal Server Error", "text/plain", "error");
                }
                return Resp::new("200 OK", "text/plain", "done");
            }
        }
    }

    // GET /takeover/<token> — serve the page only (no claim, no targetId). The
    // page JS claims via POST .../claim on load.
    if method == "GET" {
        if let Some(token) = path.strip_prefix("/takeover/") {
            if !valid_token(token) {
                return Resp::new("404 Not Found", "text/plain", "not found");
            }
            return match read_ticket(token).await {
                Ok(t) if t.expires_at_ms > now_ms() => {
                    Resp::new("200 OK", "text/html; charset=utf-8", page_html(token))
                }
                Ok(_) => Resp::new("410 Gone", "text/plain", "this takeover link has expired"),
                Err(_) => Resp::new(
                    "404 Not Found",
                    "text/plain",
                    "unknown or consumed takeover token",
                ),
            };
        }
    }

    Resp::new("404 Not Found", "text/plain", "not found")
}

/// First-come-first-serve claim, triggered by the page's on-load POST. Returns
/// the DevTools WS URL (the only sensitive bit) only to the winning claimant or
/// a matching reload; a different client gets 409.
async fn claim_response(token: &str, chrome_ws_base: &str, cookie: Option<&str>) -> Resp {
    if !valid_token(token) {
        return Resp::new("400 Bad Request", "text/plain", "bad token");
    }
    match read_ticket(token).await {
        Ok(t) if t.expires_at_ms > now_ms() => match claim(token, cookie).await {
            Ok(maybe_secret) => {
                let ws_url = format!("{chrome_ws_base}/devtools/page/{}", t.target_id);
                let body = format!("{{\"wsUrl\":{}}}", js_str(&ws_url));
                let resp = Resp::new("200 OK", "application/json", body);
                // New claimant → hand them the claim cookie (scoped to this
                // token's path). A reload (Ok(None)) already has it.
                match maybe_secret {
                    Some(secret) => resp.cookie(format!(
                        "tk_claim={secret}; Path=/takeover/{token}; HttpOnly; SameSite=Strict"
                    )),
                    None => resp,
                }
            }
            Err(_) => Resp::new(
                "409 Conflict",
                "text/plain",
                "this takeover link is already in use by someone else",
            ),
        },
        Ok(_) => Resp::new("410 Gone", "text/plain", "this takeover link has expired"),
        Err(_) => Resp::new(
            "404 Not Found",
            "text/plain",
            "unknown or consumed takeover token",
        ),
    }
}

async fn mark_done(token: &str) -> Result<()> {
    tokio::fs::create_dir_all(done_dir()).await.ok();
    tokio::fs::write(done_path(token), b"done").await?;
    Ok(())
}

/// Tokens are 32 lowercase hex chars (see `mint_token`). Reject anything else
/// so a crafted path can't escape the tokens dir or match a sentinel.
fn valid_token(token: &str) -> bool {
    token.len() == 32 && token.bytes().all(|b| b.is_ascii_hexdigit())
}

fn page_html(token: &str) -> String {
    // The WS URL is NOT embedded here — the page fetches it from POST .../claim
    // on load, so only the claiming browser ever receives the targetId.
    PAGE_TEMPLATE.replace("__TOKEN__", &js_str(token))
}

/// JSON-encode a string for safe embedding in a `<script>` literal.
fn js_str(s: &str) -> String {
    serde_json::to_string(s).unwrap_or_else(|_| "\"\"".to_string())
}

/// Self-contained takeover page. All CDP traffic is this page ↔ Chrome over the
/// WebSocket; the daemon is not in that path. `__WS_URL__`/`__TOKEN__` are
/// replaced with JSON literals before serving.
const PAGE_TEMPLATE: &str = r##"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Session takeover</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #111; color: #ddd; font: 14px/1.4 system-ui, sans-serif; }
  header { display: flex; align-items: center; gap: 12px; padding: 8px 12px; background: #1b1b1b; border-bottom: 1px solid #333; position: sticky; top: 0; }
  header b { color: #fff; }
  #status { color: #9aa; }
  #done { margin-left: auto; padding: 6px 14px; border: 0; border-radius: 6px; background: #2e7d32; color: #fff; font-weight: 600; cursor: pointer; }
  #done:disabled { background: #444; cursor: default; }
  #wrap { display: flex; justify-content: center; padding: 12px; }
  /* Canvas takes keyboard focus; outline shows it's live. */
  canvas { background: #000; max-width: 100%; height: auto; outline: 2px solid #2e7d32; cursor: default; }
  .hint { padding: 0 12px 12px; color: #888; }
  /* Vault-relay bar: a REAL login form your local Bitwarden autofills; the
     values are then typed into the remote page over CDP. */
  #vaultbar { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; padding: 8px 12px; background: #16181d; border-bottom: 1px solid #333; }
  #vaultbar .vlabel { color: #9aa; font-weight: 600; }
  #vaultbar input { background: #0d0f12; color: #ddd; border: 1px solid #333; border-radius: 5px; padding: 5px 8px; min-width: 150px; }
  #vaultbar button { padding: 5px 10px; border: 1px solid #2e7d32; border-radius: 5px; background: #14331a; color: #cfe; cursor: pointer; }
  #vaultbar button:hover { background: #1c4a26; }
</style>
</head>
<body>
<header>
  <b>Human takeover</b>
  <span id="status">connecting…</span>
  <button id="done" disabled>I'm done — hand back to agent</button>
</header>
<section id="vaultbar">
  <span class="vlabel">From your Bitwarden →</span>
  <!-- A real login form so your local extension recognizes it and autofills.
       Values are read same-origin and typed into the remote page over CDP. -->
  <form id="vault" autocomplete="on" action="#" onsubmit="return false">
    <input id="vu" type="text" name="username" autocomplete="username" placeholder="username" />
    <button type="button" data-for="vu">⏎ into focused field</button>
    <input id="vp" type="password" name="password" autocomplete="current-password" placeholder="password" />
    <button type="button" data-for="vp">⏎ into focused field</button>
    <input id="vt" type="text" name="otp" autocomplete="one-time-code" inputmode="numeric" placeholder="2FA code" />
    <button type="button" data-for="vt">⏎ into focused field</button>
  </form>
</section>
<div id="wrap"><canvas id="screen" width="1280" height="800" tabindex="0"></canvas></div>
<div class="hint">Click a field <b>in the view</b> to focus it, autofill the matching box above with your Bitwarden, then hit <b>⏎ into focused field</b> to relay it into the remote page. (Tip: add <code>chrome-takeover.lalala.casa</code> as a URI on the vault item so it auto-matches.) Anything you enter goes straight to the page over CDP — the agent never sees it. Click <b>Done</b> when finished.</div>
<script>
const TOKEN = __TOKEN__;
const canvas = document.getElementById("screen");
const ctx = canvas.getContext("2d");
const statusEl = document.getElementById("status");
const doneBtn = document.getElementById("done");

let nextId = 1;
const pending = new Map();
let lastMeta = null;       // most recent screencastFrame metadata (for coord mapping)
let ws;

function send(method, params) {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params: params || {} }));
  return id;
}
function setStatus(s) { statusEl.textContent = s; }

// --- vault relay ----------------------------------------------------------
// Read a value your local Bitwarden autofilled into our same-origin form and
// type it into whatever field is focused in the REMOTE page. Ctrl+A first so a
// re-fill replaces rather than appends.
function relay(id) {
  const el = document.getElementById(id);
  const text = (el && el.value) || "";
  if (!text) { setStatus("nothing to relay — autofill the box first, then click again"); return; }
  if (!ws || ws.readyState !== WebSocket.OPEN) { setStatus("not connected"); return; }
  const a = { key: "a", code: "KeyA", windowsVirtualKeyCode: 65, nativeVirtualKeyCode: 65, modifiers: 2 };
  send("Input.dispatchKeyEvent", { type: "keyDown", ...a });
  send("Input.dispatchKeyEvent", { type: "keyUp", ...a });
  send("Input.insertText", { text });
  setStatus("relayed " + id.slice(1) + " into the focused field");
}

function connect(wsUrl) {
  ws = new WebSocket(wsUrl);
  ws.onopen = () => {
    setStatus("connected — starting screencast");
    send("Page.enable");
    send("Runtime.enable");
    send("Page.startScreencast", { format: "jpeg", quality: 70, everyNthFrame: 1 });
    doneBtn.disabled = false;
    canvas.focus();
  };
  ws.onclose = () => setStatus("disconnected");
  ws.onerror = () => setStatus("connection error — is chrome.<base> reachable?");
  ws.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.method === "Page.screencastFrame") {
      const { data, sessionId, metadata } = msg.params;
      lastMeta = metadata;
      const img = new Image();
      img.onload = () => {
        if (canvas.width !== img.width || canvas.height !== img.height) {
          canvas.width = img.width; canvas.height = img.height;
        }
        ctx.drawImage(img, 0, 0);
      };
      img.src = "data:image/jpeg;base64," + data;
      // Ack so Chrome keeps sending frames.
      send("Page.screencastFrameAck", { sessionId });
    }
  };
}

// --- input forwarding -----------------------------------------------------
// Map a DOM event on the (CSS-scaled) canvas back to page CSS pixels. The
// screencast frame is the device-pixel image; metadata.pageScaleFactor +
// offsetTop translate to page coordinates.
function toPage(ev) {
  const rect = canvas.getBoundingClientRect();
  const sx = canvas.width / rect.width;
  const sy = canvas.height / rect.height;
  const px = (ev.clientX - rect.left) * sx;
  const py = (ev.clientY - rect.top) * sy;
  const scale = (lastMeta && lastMeta.pageScaleFactor) || 1;
  const offTop = (lastMeta && lastMeta.offsetTop) || 0;
  return { x: px / scale, y: (py - offTop) / scale };
}
const BUTTONS = { 0: "left", 1: "middle", 2: "right" };
function mouse(type, ev) {
  const { x, y } = toPage(ev);
  send("Input.dispatchMouseEvent", {
    type, x, y,
    button: BUTTONS[ev.button] || "none",
    buttons: ev.buttons,
    clickCount: type === "mousePressed" || type === "mouseReleased" ? (ev.detail || 1) : 0,
    modifiers: modBits(ev),
  });
}
function modBits(ev) {
  return (ev.altKey ? 1 : 0) | (ev.ctrlKey ? 2 : 0) | (ev.metaKey ? 4 : 0) | (ev.shiftKey ? 8 : 0);
}
canvas.addEventListener("mousemove", (e) => mouse("mouseMoved", e));
canvas.addEventListener("mousedown", (e) => { canvas.focus(); mouse("mousePressed", e); });
canvas.addEventListener("mouseup", (e) => mouse("mouseReleased", e));
canvas.addEventListener("contextmenu", (e) => e.preventDefault());
canvas.addEventListener("wheel", (e) => {
  e.preventDefault();
  const { x, y } = toPage(e);
  send("Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: -e.deltaX, deltaY: -e.deltaY, modifiers: modBits(e) });
}, { passive: false });

function keyEvent(type, ev) {
  const isChar = type === "keyDown" && ev.key.length === 1;
  send("Input.dispatchKeyEvent", {
    type: isChar ? "keyDown" : type,
    key: ev.key,
    code: ev.code,
    windowsVirtualKeyCode: ev.keyCode,
    nativeVirtualKeyCode: ev.keyCode,
    text: ev.key.length === 1 ? ev.key : undefined,
    modifiers: modBits(ev),
  });
}
canvas.addEventListener("keydown", (e) => { e.preventDefault(); keyEvent("keyDown", e); });
canvas.addEventListener("keyup", (e) => { e.preventDefault(); keyEvent("keyUp", e); });

// --- done -----------------------------------------------------------------
doneBtn.addEventListener("click", async () => {
  doneBtn.disabled = true;
  setStatus("handing back to agent…");
  try {
    await fetch("/takeover/" + TOKEN + "/done", { method: "POST" });
    if (ws) { try { send("Page.stopScreencast"); } catch {} ws.close(); }
    setStatus("done — you can close this tab");
  } catch {
    setStatus("failed to signal done — try again");
    doneBtn.disabled = false;
  }
});

document.querySelectorAll("#vault button[data-for]").forEach((b) => {
  b.addEventListener("click", (e) => { e.preventDefault(); relay(b.getAttribute("data-for")); });
});

// Claim the session on load (POST, so passive unfurl/prefetch GETs never claim
// it). Only on success do we receive the WS URL and start the screencast.
async function start() {
  setStatus("claiming session…");
  let r;
  try { r = await fetch("/takeover/" + TOKEN + "/claim", { method: "POST" }); }
  catch { setStatus("network error reaching the takeover server"); return; }
  if (r.status === 409) {
    setStatus("This takeover link is already in use by someone else.");
    return;
  }
  if (!r.ok) { setStatus("could not claim this link (HTTP " + r.status + ")"); return; }
  let wsUrl;
  try { wsUrl = (await r.json()).wsUrl; } catch { setStatus("bad claim response"); return; }
  if (!wsUrl) { setStatus("no session URL returned"); return; }
  connect(wsUrl);
}
start();
</script>
</body>
</html>
"##;
