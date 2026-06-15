# browser-session-mcp

An MCP server that gives each caller an isolated browser session against a
shared persistent Chrome, and captures every console + network event to disk
losslessly regardless of MCP transport churn.

## Why

Existing Chrome-over-MCP solutions couple a "session" to the transport layer
(SSE session, WebSocket, streamable-http session id). When that transport
reconnects — and transports do reconnect, constantly — the browser goes with
it. You lose cookies, tabs, and any state the agent was building up.

This server inverts the pattern: **the session is a tool argument**, not a
transport concept. An agent calls `open_browser_session` once, gets back a
`sessionId`, and passes that id into every subsequent tool call. The session
lives as long as the underlying Chrome process does — transport reconnects
don't touch it.

Internally each session is a Puppeteer `BrowserContext`, an incognito-style
isolated profile (own cookies, storage, tabs). Contexts are cheap; Chrome can
hold many at once. Two agents running in parallel open two sessions → two
contexts → zero shared state.

## Architecture

Three processes co-operate:

```
[Chrome :9222] ←CDP─ [browser-session-listener]   (host systemd, Restart=always)
                              │
                              ▼  NDJSON files
                  /var/lib/browser-session-mcp/logs/<sid>/<seq>-<targetId>.ndjson
                              ▲
                              │
                  [browser-session-mcp]   (stdio MCP server)
                  list_console_messages / list_network_requests read these files
```

Event capture lives in the listener daemon, not the MCP subprocess. The
subprocess can be killed and respawned freely (mcp-proxy churn, executor cache
eviction, etc.) — sessions persist in Chrome and event logs persist on disk.

A periodic reaper (`browser-session-reaper`) closes BrowserContexts that have
been idle longer than `MAX_IDLE_HOURS` (default 24) and removes their log
directories.

## Storage layout

```
/var/lib/browser-session-mcp/
├── state.json                        # session lastUsedAt — read by the reaper
├── logs/
│   └── <sessionId>/
│       ├── 00001-<targetId>.ndjson   # per-visit event log
│       ├── 00002-<targetId>.ndjson
│       └── ...
└── states/                           # saved cookies (mode 0700)
    ├── github.json                   # mode 0600
    └── ...
```

A **visit** is one top-level navigation in one tab — the boundary is CDP
`Page.frameNavigated` for the main frame. Each visit gets its own NDJSON file
whose first line is a `{"kind":"visit",seq,targetId,url,openedAt}` header,
followed by one line per console + network event. Document requests are
attributed to the visit they triggered (handled by retroactively reassigning
in-flight CDP records when frameNavigated fires).

## Running

```
BROWSER_URL=http://localhost:9222 browser-session-mcp
```

Talks MCP over stdio. Expects a Chrome exposing the DevTools Protocol at
`BROWSER_URL`, e.g. `chrome-headless-shell --remote-debugging-port=9222`.

Environment:

- `BROWSER_URL` (required) — DevTools HTTP endpoint
- `STATE_FILE` — defaults to `/var/lib/browser-session-mcp/state.json`
- `LOGS_DIR` — defaults to `/var/lib/browser-session-mcp/logs`
- `STATES_DIR` — defaults to `/var/lib/browser-session-mcp/states`

The package ships two companion binaries:

- `browser-session-listener` — long-running CDP listener daemon. Same env
  vars; ignores `STATE_FILE`/`STATES_DIR`. Run as a systemd service with
  `Restart=always` and `After=chrome-headless`.
- `browser-session-reaper` — one-shot idle-session sweeper. Reads `STATE_FILE`,
  honors `MAX_IDLE_HOURS` (default 24). Run on a 12h timer.
- `browser-session-takeover` — long-running HTTP server for the human-takeover
  page. Env: `TAKEOVER_BIND` (default `127.0.0.1:9223`), `TAKEOVER_DIR` (default
  `/var/lib/browser-session-mcp/takeover`), `CHROME_WS_BASE` (required, e.g.
  `wss://chrome.<base>`). All CDP traffic is browser↔Chrome; this daemon only
  serves the page and accepts the "Done" POST.

## Tool surface (21 tools)

**Session lifecycle**

- `open_browser_session({ viewport?, useMobileUA? })` → `{ sessionId, pageCount, activeUrl }`
- `close_browser_session({ sessionId })`
- `list_browser_sessions()`

Every session gets an auto-applied UA + matching `Sec-CH-UA-*` Client Hints, so
`HeadlessChrome` never leaks to sites. The default spoof is Chrome on Linux
desktop; pass `useMobileUA: true` to get Chrome on Android (Pixel 8) instead.
This is UA-only — viewport, touch, and DPR are unchanged, so combine with the
`viewport` arg if you also want a phone-sized canvas. The override applies to
every page in the session (initial + later `new_page`) and survives MCP
subprocess restarts.

**Tabs**

- `new_page({ sessionId, url? })`
- `list_pages({ sessionId })`

**Navigation**

- `navigate({ sessionId, url, waitUntil?, timeout? })`

**Capture**

- `take_screenshot({ sessionId, fullPage? })` — PNG as base64
- `take_snapshot({ sessionId })` — accessibility tree

**Interaction**

- `click({ sessionId, selector, timeout? })`
- `type({ sessionId, selector, text, delay?, clear? })`
- `wait_for({ sessionId, selector? | text?, timeout? })`
- `evaluate({ sessionId, expression })` — runs JS in the page, returns the value

**Per-visit logs**

- `list_visits({ sessionId })` — visit headers in chronological order
- `list_console_messages({ sessionId, visit?, limit? })`
- `list_network_requests({ sessionId, visit?, limit? })`

**Human takeover** (login/passkey without the agent seeing credentials)

- `request_human_takeover({ sessionId, ttl? })` → `{ url, token, expiresAtMs }` — non-blocking; mints a link
- `await_human_takeover({ token, timeout? })` → `{ completed }` — blocks until the human clicks Done

**Saved cookie states**

- `save_browser_state({ sessionId, name })`
- `load_browser_state({ sessionId, name })`
- `list_browser_states()`
- `delete_browser_state({ name })`

Most tools take `sessionId` as their first argument; the lifecycle,
saved-state-listing, and `await_human_takeover` tools don't.

## Human-takeover workflow

When a flow needs credentials the agent must not handle (passwords, passkeys),
hand the live page to a human instead of automating the login:

```ts
const sid = (await tools.browser_session_mcp.open_browser_session({}))
  .structuredContent.sessionId;
await tools.browser_session_mcp.navigate({
  sessionId: sid,
  url: "https://accounts.google.com",
});

// Mint a link and SHOW IT TO THE USER (this call returns immediately).
const { url, token } = (
  await tools.browser_session_mcp.request_human_takeover({ sessionId: sid })
).structuredContent;
// → present `url`; the user opens it, sees a live view of the page, logs in
//   themselves (passkey/password/2FA), and clicks "Done".

// Block until they finish, then continue against the now-authenticated session.
await tools.browser_session_mcp.await_human_takeover({
  token,
  timeout: 600000,
});
await tools.browser_session_mcp.navigate({
  sessionId: sid,
  url: "https://tagmanager.google.com",
});
```

How it works: `request_human_takeover` writes a ticket (sessionId + the active
page's CDP targetId) to `${TAKEOVER_DIR}/tokens/<token>.json` and returns
`${TAKEOVER_BASE_URL}/takeover/<token>`. The `browser-session-takeover` daemon
serves that page; its JavaScript opens a WebSocket straight to `CHROME_WS_BASE`
(the same `chrome.<base>` DevTools endpoint), runs `Page.startScreencast`,
renders frames to a canvas, and forwards the human's mouse/keyboard as
`Input.dispatch*` — so credentials go page-direct and never touch the agent or
this daemon. "Done" POSTs back, dropping `${TAKEOVER_DIR}/done/<token>`, which
unblocks `await_human_takeover`.

## Saved-state workflow

For sites where you don't want to log in every session:

```ts
// Once: log in interactively, save the cookies
const sid = (await tools.browser_session_mcp.open_browser_session({}))
  .structuredContent.sessionId;
await tools.browser_session_mcp.navigate({
  sessionId: sid,
  url: "https://github.com/login",
});
// ... fill out form via type/click, handle 2FA ...
await tools.browser_session_mcp.save_browser_state({
  sessionId: sid,
  name: "github",
});

// Later, in any new session:
const sid2 = (await tools.browser_session_mcp.open_browser_session({}))
  .structuredContent.sessionId;
await tools.browser_session_mcp.load_browser_state({
  sessionId: sid2,
  name: "github",
});
await tools.browser_session_mcp.navigate({
  sessionId: sid2,
  url: "https://github.com/foo",
});
// already logged in
```

Cookies are saved as JSON at `/var/lib/browser-session-mcp/states/<name>.json`
in plaintext (mode 0600, dir mode 0700). v1 is cookies-only; localStorage is
not yet supported, but the on-disk schema reserves an `origins[]` field for
forward-compat.

## Operational notes

- The listener daemon is the single source of truth for console + network
  events. If it's down, events that fire during its downtime are lost.
  `Restart=always` keeps that window short (≈ seconds).
- Sessions survive transport-layer churn but not Chrome restarts. If Chrome
  restarts, all `BrowserContext`s are gone — agents need to call
  `open_browser_session` again.
- The reaper deletes a session's NDJSON folder when it closes the context, so
  log space doesn't grow unboundedly.
- There's no per-visit log rotation. A single very long-lived visit on a
  noisy SPA can grow its NDJSON file without bound; in practice this hasn't
  been a problem.
