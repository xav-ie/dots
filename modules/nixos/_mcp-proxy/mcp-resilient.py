"""Resilience shim for mcp-proxy named servers.

mcp-proxy 0.8.2 runs every named server in one process and has no per-server
error isolation: if a single backend exits non-zero while a session is being
set up (e.g. slack-mcp-server dying on an expired token), the failure
propagates through the shared anyio TaskGroup and crashes the whole proxy
container — every source then reports 0 tools. See the `just slack-tokens`
recipe for that exact case.

This shim wraps a backend command: `mcp-resilient <cmd> [args...]`. It runs the
real server with inherited stdio (fully transparent while healthy). If the real
server fails to start / exits non-zero, we degrade to a minimal MCP stdio
server that advertises no tools instead of leaving a dead pipe — so one bad egg
only shows up as an empty source, and the rest of the proxy keeps serving.

Relies on the real server checking its config/auth and exiting BEFORE it reads
stdin (slack-mcp-server does), so the client's `initialize` request is still
buffered in the pipe for the stub to answer.
"""

import json
import subprocess
import sys

# MCP stdio transport is newline-delimited JSON-RPC (one message per line).
_EMPTY_RESULTS = {
    "tools/list": {"tools": []},
    "resources/list": {"resources": []},
    "resources/templates/list": {"resourceTemplates": []},
    "prompts/list": {"prompts": []},
    "ping": {},
}


def _stub():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        mid = msg.get("id")
        if mid is None:
            continue  # notification (e.g. notifications/initialized) — ignore
        method = msg.get("method", "")
        if method == "initialize":
            params = msg.get("params") or {}
            result = {
                "protocolVersion": params.get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}, "resources": {}, "prompts": {}},
                "serverInfo": {"name": "unavailable", "version": "0"},
            }
        else:
            result = _EMPTY_RESULTS.get(method, {})
        sys.stdout.write(
            json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n"
        )
        sys.stdout.flush()


def main():
    if len(sys.argv) < 2:
        sys.exit(2)
    try:
        code = subprocess.call(sys.argv[1:])  # inherits stdio + env
    except FileNotFoundError:
        code = 127
    if code != 0:
        _stub()


if __name__ == "__main__":
    main()
