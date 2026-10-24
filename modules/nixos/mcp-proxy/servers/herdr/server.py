"""MCP server for driving praesidium's herdr: see what agents are doing,
prompt them, and spawn, move, rename, or close them.

Talks to herdr's socket API directly (one JSON request per connection); the
full method list is in `herdr api schema --json`, reachable via `call`.
Workspaces may be given by id (w3) or label (general). A caller running inside
herdr finds its own ids in $HERDR_WORKSPACE_ID/$HERDR_TAB_ID/$HERDR_PANE_ID.
"""

import asyncio
import collections
import glob
import json
import os
import re
import sqlite3

from mcp.server.fastmcp import FastMCP

SOCKET = os.environ["HERDR_SOCKET_PATH"]
# Waits stay under the client's request timeout (as in the agent server);
# callers poll longer work with wait_agent.
MAX_WAIT_S = 55
# The container's HOME is not the herdr user's, so `~` in cwds expands to this.
HERDR_HOME = os.environ["HERDR_HOME"]
# Read-only mounts of the agents' own session stores, for last_response.
CLAUDE_PROJECTS = os.environ.get("CLAUDE_PROJECTS_DIR", f"{HERDR_HOME}/.claude/projects")
OPENCODE_DB = os.environ.get("OPENCODE_DB", f"{HERDR_HOME}/.local/share/opencode/opencode.db")
mcp = FastMCP("herdr")


async def rpc(method, params=None):
    reader, writer = await asyncio.open_unix_connection(SOCKET, limit=64 * 1024 * 1024)
    try:
        writer.write(json.dumps({"id": "1", "method": method, "params": params or {}}).encode() + b"\n")
        await writer.drain()
        line = await reader.readline()
    finally:
        writer.close()
    if not line:
        raise ConnectionError(f"{method}: herdr closed the socket without replying")
    resp = json.loads(line)
    if "error" in resp:
        raise HerdrError(method, resp["error"]["code"], resp["error"]["message"])
    return resp["result"]


class HerdrError(RuntimeError):
    def __init__(self, method, code, message):
        super().__init__(f"{method}: {code}: {message}")
        self.code = code


async def snapshot():
    return (await rpc("session.snapshot"))["snapshot"]


async def workspace_id(ws):
    if ws is None:
        return None
    workspaces = (await snapshot())["workspaces"]
    ids = [w["workspace_id"] for w in workspaces if ws in (w["workspace_id"], w["label"])]
    if len(ids) != 1:
        labels = [w["label"] for w in workspaces]
        raise ValueError(f"workspace {ws!r} matches {ids or 'nothing'}; workspaces: {labels}")
    return ids[0]


PANE_ID = re.compile(r"^w\w+:p\w+$")


async def resolve(target):
    """A pane id, a tab id, or a tab label (exact, else a unique case-insensitive
    substring) to the tab's agent pane. Anything else (an agent name) is passed
    through for herdr to resolve."""
    if PANE_ID.match(target):
        return target
    snap = await snapshot()
    tabs = [t for t in snap["tabs"] if t["tab_id"] == target]
    if not tabs:
        low = target.lower()
        tabs = [t for t in snap["tabs"] if t["label"].lower() == low] or [t for t in snap["tabs"] if low in t["label"].lower()]
    if len(tabs) > 1:
        raise ValueError(f"{target!r} matches tabs {[t['label'] for t in tabs]}; pass a longer label or a pane id")
    if not tabs:
        return target
    panes = [p for p in snap["panes"] if p["tab_id"] == tabs[0]["tab_id"]]
    agents = [p for p in panes if p.get("agent")]
    return (agents or panes)[0]["pane_id"]


BOX = re.compile(r"[─-▟]")  # box drawing and block elements


def clean(text):
    """Drop TUI chrome from a pane read: box/block characters, a right-hand
    status sidebar (text that starts at the same column, after a wide gap, on
    many lines), bar-only lines, trailing spaces and runs of blank lines."""
    lines = [BOX.sub(" ", line).rstrip() for line in text.splitlines()]
    starts = collections.Counter(m.end() for line in lines for m in [re.search(r"\S {8,}(?=\S)", line)] if m)
    if starts:
        col, hits = starts.most_common(1)[0]
        if hits >= 3 and hits >= 0.15 * sum(1 for line in lines if line.strip()):
            lines = [line[:col].rstrip() if len(line) > col and line[col - 8:col].isspace() else line for line in lines]
    out, blank = [], 0
    for line in lines:
        blank = blank + 1 if not line.strip() else 0
        if blank <= 1:
            out.append(line)
    # Dedent by the common left margin left behind by stripped borders.
    margin = min((len(line) - len(line.lstrip()) for line in out if line.strip()), default=0)
    return "\n".join(line[margin:] for line in out).strip("\n")


async def tail(target, lines, raw=False):
    r = await rpc("agent.read", {"target": target, "source": "recent", "lines": lines})
    text = r["read"]["text"].rstrip()
    return text if raw else clean(text)


def claude_last_response(session_id):
    """Assistant text since the last real user prompt in a Claude Code
    transcript, read backwards so long transcripts stay cheap."""
    paths = glob.glob(f"{CLAUDE_PROJECTS}/*/{session_id}.jsonl")
    if not paths:
        raise FileNotFoundError(f"no Claude transcript for session {session_id} under {CLAUDE_PROJECTS}")
    texts = []
    for record in reversed_jsonl(paths[0]):
        kind = record.get("type")
        content = (record.get("message") or {}).get("content")
        if kind == "assistant" and isinstance(content, list):
            texts += [c["text"] for c in reversed(content) if c.get("type") == "text" and c.get("text", "").strip()]
        # Tool results come back as user records; a typed prompt ends the turn.
        elif (
            kind == "user"
            and not record.get("isMeta")
            and (isinstance(content, str) or any(c.get("type") == "text" for c in content or []))
        ):
            break
    return "\n\n".join(reversed(texts))


def reversed_jsonl(path, chunk=1 << 20):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        pos, rest = f.tell(), b""
        while pos > 0:
            step = min(chunk, pos)
            pos -= step
            f.seek(pos)
            lines = (f.read(step) + rest).split(b"\n")
            rest = lines.pop(0)
            for line in reversed(lines):
                if line.strip():
                    yield json.loads(line)
        if rest.strip():
            yield json.loads(rest)


def opencode_last_response(session_id):
    """Text of the newest assistant message with text in an opencode session.
    The database is opened read-only in place (it is too big to copy); its
    -shm file already exists, which SQLite needs to read WAL on a read-only
    mount."""
    query = "select data from session_message where session_id = ? and type = 'assistant' order by seq desc limit 50"
    db = sqlite3.connect(f"file:{OPENCODE_DB}?mode=ro", uri=True)
    try:
        try:
            rows = db.execute(query, (session_id,)).fetchall()
        except sqlite3.OperationalError:
            # A mount SQLite can't map the -shm of: read without the WAL, which
            # may miss the newest messages until opencode checkpoints.
            db.close()
            db = sqlite3.connect(f"file:{OPENCODE_DB}?mode=ro&immutable=1", uri=True)
            rows = db.execute(query, (session_id,)).fetchall()
        for (data,) in rows:
            texts = [c["text"] for c in json.loads(data).get("content", []) if c.get("type") == "text" and c.get("text", "").strip()]
            if texts:
                return "\n\n".join(texts)
    finally:
        db.close()
    return ""


def ms(seconds):
    return int(min(seconds, MAX_WAIT_S) * 1000)


async def settle(method, params, target, tail_lines, verbose=False, raw=False):
    """Run a waiting agent call; on timeout report the current state instead
    of failing, so the caller can keep polling with wait_agent. Returns
    {status, timed_out, tail}; verbose adds herdr's full result."""
    timed_out = False
    try:
        result = await rpc(method, params)
    except HerdrError as e:
        if e.code != "timeout":
            raise
        timed_out = True
        result = {"timed_out": True, "agent": (await rpc("agent.get", {"target": target}))["agent"]}
    agent = result.get("agent") if isinstance(result, dict) else None
    if not agent:
        agent = (await rpc("agent.get", {"target": target}))["agent"]
    out = {"status": agent.get("agent_status"), "timed_out": timed_out, "tail": await tail(target, tail_lines, raw)}
    if verbose:
        out["result"] = result
    return out


async def submit(target, text):
    """agent.prompt, plus the Enter a multi-line prompt needs: Claude Code
    takes multi-line input as a paste and leaves it unsent."""
    await rpc("agent.prompt", {"target": target, "text": text})
    if "\n" in text:
        await asyncio.sleep(0.5)
        await rpc("agent.send_keys", {"target": target, "keys": ["Enter"]})


@mcp.tool()
async def list_panes(workspace: str | None = None, query: str | None = None, tail_lines: int = 0) -> dict:
    """Overview of every pane: workspace/tab labels, agent, status, title, cwd,
    and agent session id. query keeps panes whose tab label, title, agent or
    cwd contains it (case-insensitive). tail_lines > 0 also includes the last
    N lines of each agent pane's output, cleaned of TUI chrome."""
    snap = await snapshot()
    ws_label = {w["workspace_id"]: w["label"] for w in snap["workspaces"]}
    tab_label = {t["tab_id"]: t["label"] for t in snap["tabs"]}
    ws = workspace and await workspace_id(workspace)
    low = query and query.lower()
    out = []
    for p in snap["panes"]:
        if ws and p["workspace_id"] != ws:
            continue
        haystack = " ".join(str(v) for v in (tab_label.get(p["tab_id"]), p.get("terminal_title_stripped"), p.get("agent"), p.get("foreground_cwd") or p.get("cwd")))
        if low and low not in haystack.lower():
            continue
        row = {
            "pane_id": p["pane_id"],
            "workspace": ws_label.get(p["workspace_id"]),
            "tab_id": p["tab_id"],
            "tab": tab_label.get(p["tab_id"]),
            "agent": p.get("agent"),
            "status": p.get("agent_status"),
            "title": p.get("terminal_title_stripped"),
            "cwd": p.get("foreground_cwd") or p.get("cwd"),
            "session_id": (p.get("agent_session") or {}).get("value"),
            "focused": p["focused"],
        }
        if tail_lines and p.get("agent"):
            row["tail"] = await tail(p["pane_id"], tail_lines)
        out.append(row)
    return {"panes": out}


@mcp.tool()
async def read_pane(pane_id: str, lines: int = 80, source: str = "recent", raw: bool = False) -> str:
    """Read a pane's output (pane id, tab id, or tab label). source: visible |
    recent | recent_unwrapped. Cleaned of TUI chrome (borders, status sidebar,
    blank runs) unless raw; use raw for exact screen layout like prompts."""
    r = await rpc("pane.read", {"pane_id": await resolve(pane_id), "source": source, "lines": lines})
    text = r["read"]["text"]
    return text if raw else clean(text)


@mcp.tool()
async def prompt_agent(
    target: str, text: str, wait: bool = True, timeout_s: int = MAX_WAIT_S, tail_lines: int = 60, verbose: bool = False
) -> dict:
    """Submit a prompt to an agent (pane id like w3:p4, tab label, or agent
    name). With wait, blocks (max 55s) until it is idle/done/blocked and
    returns {status, timed_out, tail}; if still working, timed_out is set and
    wait_agent continues. Without wait, returns its status a moment after
    submitting, so a prompt that didn't land shows as still idle. verbose
    adds herdr's full result. Rejected if the agent is blocked on a permission
    prompt; use send_keys for that. last_response reads its reply as text."""
    target = await resolve(target)
    if "\n" in text:
        await submit(target, text)
    elif wait:
        params = {"target": target, "text": text, "wait": {"timeout_ms": ms(timeout_s)}}
        return await settle("agent.prompt", params, target, tail_lines, verbose)
    else:
        await rpc("agent.prompt", {"target": target, "text": text})
    if not wait:
        try:
            await rpc("agent.wait", {"target": target, "until": ["working", "blocked"], "timeout_ms": 3000})
        except HerdrError as e:
            if e.code != "timeout":
                raise
        return {"submitted": True, "status": (await rpc("agent.get", {"target": target}))["agent"].get("agent_status")}
    # Give the submitted prompt a moment to flip the agent to working.
    await asyncio.sleep(1)
    return await settle("agent.wait", {"target": target, "timeout_ms": ms(timeout_s)}, target, tail_lines, verbose)


@mcp.tool()
async def wait_agent(
    target: str, until: list[str] | None = None, timeout_s: int = MAX_WAIT_S, tail_lines: int = 60, verbose: bool = False
) -> dict:
    """Wait (max 55s) for an agent (pane id, tab label, or agent name) to reach
    a status (idle, working, blocked, done; default idle/done/blocked). Returns
    {status, timed_out, tail}; call again while timed_out to keep waiting.
    verbose adds herdr's full result."""
    target = await resolve(target)
    params = {"target": target, "timeout_ms": ms(timeout_s)}
    if until:
        params["until"] = until
    return await settle("agent.wait", params, target, tail_lines, verbose)


@mcp.tool()
async def last_response(target: str) -> dict:
    """An agent's last reply as plain text (pane id, tab label, or agent name),
    read from its own session (Claude Code transcript or opencode database),
    not the screen. Returns {status, agent, response}; while status is working
    the reply may still be growing."""
    pane = (await rpc("agent.get", {"target": await resolve(target)}))["agent"]
    kind, session = pane.get("agent"), (pane.get("agent_session") or {}).get("value")
    if not session:
        raise ValueError(f"{target!r} reports no agent session")
    if kind == "claude":
        response = await asyncio.to_thread(claude_last_response, session)
    elif kind == "opencode":
        response = await asyncio.to_thread(opencode_last_response, session)
    else:
        raise ValueError(f"last_response does not know how to read {kind!r} sessions")
    return {"status": pane.get("agent_status"), "agent": kind, "response": response}


@mcp.tool()
async def send_keys(pane_id: str, keys: list[str] | None = None, text: str | None = None) -> dict:
    """Send literal text and/or keys (e.g. ["ctrl+c"], ["Enter"], ["1"]) to a
    pane (pane id, tab id, or tab label). Useful for answering permission
    prompts or interrupting."""
    params = {"pane_id": await resolve(pane_id)}
    if text:
        params["text"] = text
    if keys:
        params["keys"] = keys
    return await rpc("pane.send_input", params)


@mcp.tool()
async def spawn_agent(
    cwd: str,
    label: str,
    workspace: str,
    prompt: str | None = None,
    resume: str | None = None,
    kind: str = "claude",
    args: list[str] | None = None,
    focus: bool = False,
) -> dict:
    """Open a new tab and start an agent in it. Workspaces group tabs by
    project; pass the one the work belongs to, by label or id. list_panes
    shows existing labels, and
    an unknown name errors with the full list. prompt is submitted to the agent
    once it is ready, so it may contain any text; resume is a Claude session id
    to --resume. Returns the new tab and pane ids, agent name, and whether it
    became ready and received the prompt (both false if the agent is still
    starting after 30s)."""
    created = await rpc(
        "tab.create",
        {"workspace_id": await workspace_id(workspace), "cwd": re.sub(r"^~(?=/|$)", HERDR_HOME, cwd), "label": label, "focus": focus},
    )
    tab_id = created["tab"]["tab_id"]
    pane_id = next(p["pane_id"] for p in (await snapshot())["panes"] if p["tab_id"] == tab_id)
    argv = list(args or [])
    if resume:
        argv += ["--resume", resume]
    # herdr names: lowercase letter first, [a-z0-9_-], at most 32 chars. Tab ids
    # carry uppercase letters (w3:t1D), and the suffix keeps repeated labels apart.
    suffix = re.sub(r"[^a-z0-9]+", "", tab_id.split(":")[-1].lower())
    slug = re.sub(r"[^a-z0-9_-]+", "-", label.lower()).strip("-_")
    slug = slug if slug[:1].isalpha() else f"agent-{slug}".rstrip("-")
    name = f"{slug[: 31 - len(suffix)].rstrip('-_')}-{suffix}"
    try:
        await rpc("agent.start", {"name": name, "kind": kind, "pane_id": pane_id, "args": argv})
    except Exception:
        await rpc("tab.close", {"tab_id": tab_id})
        raise
    # The socket returns with launch_pending; the CLI waits for readiness, so do the same.
    ready = False
    for _ in range(60):
        if ready := (await rpc("agent.get", {"target": pane_id}))["agent"].get("interactive_ready", False):
            break
        await asyncio.sleep(0.5)
    # Delivered as input, not argv: agent.start rejects arguments the target
    # shell can't quote safely, which any multi-line prompt trips.
    prompted = False
    if prompt and ready:
        await submit(pane_id, prompt)
        prompted = True
    return {"tab_id": tab_id, "pane_id": pane_id, "agent": name, "ready": ready, "prompted": prompted}


@mcp.tool()
async def move_tab(tab_id: str, workspace: str) -> dict:
    """Move a tab to another workspace, keeping its label. Panes are re-split
    side by side; the original layout is not preserved."""
    ws = await workspace_id(workspace)
    snap = await snapshot()
    label = next((t["label"] for t in snap["tabs"] if t["tab_id"] == tab_id), None)
    panes = [p["pane_id"] for p in snap["panes"] if p["tab_id"] == tab_id]
    if label is None or not panes:
        raise ValueError(f"no tab {tab_id!r} with panes")
    # ponytail: panes are appended as right splits; use layout.export/apply if layouts matter.
    first = await rpc(
        "pane.move",
        {"pane_id": panes[0], "destination": {"type": "new_tab", "workspace_id": ws, "label": label}},
    )
    new_tab = first["move_result"]["created_tab"]["tab_id"]
    for p in panes[1:]:
        await rpc("pane.move", {"pane_id": p, "destination": {"type": "tab", "tab_id": new_tab, "split": "right"}})
    return {"tab_id": new_tab, "panes": panes}


@mcp.tool()
async def rename_tab(tab_id: str, label: str) -> dict:
    """Rename a tab."""
    return await rpc("tab.rename", {"tab_id": tab_id, "label": label})


@mcp.tool()
async def close(pane_id: str | None = None, tab_id: str | None = None) -> dict:
    """Close a pane or a whole tab. Kills whatever is running in it."""
    if tab_id:
        return await rpc("tab.close", {"tab_id": tab_id})
    return await rpc("pane.close", {"pane_id": pane_id})


@mcp.tool()
async def call(method: str, params: dict | None = None) -> dict:
    """Raw herdr socket API call for anything the other tools don't cover
    (workspace.create/rename/close, tab.move reorder, pane.split, layout.*,
    agent.rename, ...). Schema: `herdr api schema --json`."""
    return await rpc(method, params)


if __name__ == "__main__":
    mcp.run()
