"""MCP server for driving praesidium's herdr: see what agents are doing,
prompt them, and spawn, move, rename, or close them.

Talks to herdr's socket API directly (one JSON request per connection); the
full method list is in `herdr api schema --json`, reachable via `call`.
Workspaces may be given by id (w3) or label (general). A caller running inside
herdr finds its own ids in $HERDR_WORKSPACE_ID/$HERDR_TAB_ID/$HERDR_PANE_ID.
"""

import asyncio
import json
import os
import re

from mcp.server.fastmcp import FastMCP

SOCKET = os.environ["HERDR_SOCKET_PATH"]
# Waits stay under the client's request timeout (as in the agent server);
# callers poll longer work with wait_agent.
MAX_WAIT_S = 55
# The container's HOME is not the herdr user's, so `~` in cwds expands to this.
HERDR_HOME = os.environ["HERDR_HOME"]
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
    ids = [w["workspace_id"] for w in (await snapshot())["workspaces"] if ws in (w["workspace_id"], w["label"])]
    if len(ids) != 1:
        raise ValueError(f"workspace {ws!r} matches {ids or 'nothing'}")
    return ids[0]


async def tail(target, lines):
    r = await rpc("agent.read", {"target": target, "source": "recent", "lines": lines})
    return r["read"]["text"].rstrip()


def ms(seconds):
    return int(min(seconds, MAX_WAIT_S) * 1000)


async def settle(method, params, target, tail_lines):
    """Run a waiting agent call; on timeout report the current state instead
    of failing, so the caller can keep polling with wait_agent."""
    try:
        result = await rpc(method, params)
    except HerdrError as e:
        if e.code != "timeout":
            raise
        result = {"timed_out": True, "agent": (await rpc("agent.get", {"target": target}))["agent"]}
    return {"result": result, "tail": await tail(target, tail_lines)}


async def submit(target, text):
    """agent.prompt, plus the Enter a multi-line prompt needs: Claude Code
    takes multi-line input as a paste and leaves it unsent."""
    await rpc("agent.prompt", {"target": target, "text": text})
    if "\n" in text:
        await asyncio.sleep(0.5)
        await rpc("agent.send_keys", {"target": target, "keys": ["Enter"]})


@mcp.tool()
async def list_panes(workspace: str | None = None, tail_lines: int = 0) -> dict:
    """Overview of every pane: workspace/tab labels, agent, status, title, cwd,
    and agent session id. tail_lines > 0 also includes the last N lines of each
    agent pane's output (use to summarize what agents are doing)."""
    snap = await snapshot()
    ws_label = {w["workspace_id"]: w["label"] for w in snap["workspaces"]}
    tab_label = {t["tab_id"]: t["label"] for t in snap["tabs"]}
    ws = workspace and await workspace_id(workspace)
    out = []
    for p in snap["panes"]:
        if ws and p["workspace_id"] != ws:
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
async def read_pane(pane_id: str, lines: int = 80, source: str = "recent") -> str:
    """Read a pane's output. source: visible | recent | recent_unwrapped."""
    r = await rpc("pane.read", {"pane_id": pane_id, "source": source, "lines": lines})
    return r["read"]["text"]


@mcp.tool()
async def prompt_agent(target: str, text: str, wait: bool = True, timeout_s: int = MAX_WAIT_S, tail_lines: int = 60) -> dict:
    """Submit a prompt to an agent (pane id like w3:p4, or agent name). With wait,
    blocks (max 55s) until it is idle/done/blocked and returns its status plus
    the last tail_lines of output; if still working, result.timed_out is set
    and wait_agent continues. Rejected if the agent is blocked on a
    permission prompt; use send_keys for that."""
    if "\n" in text:
        await submit(target, text)
        if not wait:
            return {"result": "submitted"}
        # Give the submitted prompt a moment to flip the agent to working.
        await asyncio.sleep(1)
        return await settle("agent.wait", {"target": target, "timeout_ms": ms(timeout_s)}, target, tail_lines)
    params = {"target": target, "text": text}
    if not wait:
        return {"result": await rpc("agent.prompt", params)}
    params["wait"] = {"timeout_ms": ms(timeout_s)}
    return await settle("agent.prompt", params, target, tail_lines)


@mcp.tool()
async def wait_agent(target: str, until: list[str] | None = None, timeout_s: int = MAX_WAIT_S, tail_lines: int = 60) -> dict:
    """Wait (max 55s) for an agent to reach a status (idle, working, blocked,
    done; default idle/done/blocked), then return the tail of its output.
    result.timed_out is set if it hasn't yet; call again to keep waiting."""
    params = {"target": target, "timeout_ms": ms(timeout_s)}
    if until:
        params["until"] = until
    return await settle("agent.wait", params, target, tail_lines)


@mcp.tool()
async def send_keys(pane_id: str, keys: list[str] | None = None, text: str | None = None) -> dict:
    """Send literal text and/or keys (e.g. ["ctrl+c"], ["Enter"], ["1"]) to a
    pane. Useful for answering permission prompts or interrupting."""
    params = {"pane_id": pane_id}
    if text:
        params["text"] = text
    if keys:
        params["keys"] = keys
    return await rpc("pane.send_input", params)


@mcp.tool()
async def spawn_agent(
    cwd: str,
    label: str,
    workspace: str | None = None,
    prompt: str | None = None,
    resume: str | None = None,
    kind: str = "claude",
    args: list[str] | None = None,
    focus: bool = False,
) -> dict:
    """Open a new tab and start an agent in it (default workspace: the focused
    one). prompt is submitted to the agent once it is ready, so it may contain
    any text; resume is a Claude session id to --resume. Returns the new tab and
    pane ids, agent name, and whether it became ready and received the prompt
    (both false if the agent is still starting after 30s)."""
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
