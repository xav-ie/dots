#!/usr/bin/env python3
"""Fail the build if a tool's reworded MCP description regresses.

Loads expected-descriptions.json (one entry per tool this package's
default.nix patches via tool-descriptions.patch) and compares it against
what jira_mcp/confluence_mcp actually register. A tool rename/reword in a
mcp-atlassian version bump makes this fail loudly instead of silently
reverting to upstream's wording.
"""

import asyncio
import json
import sys
from pathlib import Path

from mcp_atlassian.servers.confluence import confluence_mcp
from mcp_atlassian.servers.jira import jira_mcp


async def main() -> int:
    expected = json.loads(
        (Path(__file__).parent / "expected-descriptions.json").read_text()
    )

    jira_tools = await jira_mcp.list_tools()
    confluence_tools = await confluence_mcp.list_tools()

    actual: dict[str, str] = {}
    for tool in jira_tools:
        actual[f"jira_{tool.name}"] = tool.description or ""
    for tool in confluence_tools:
        actual[f"confluence_{tool.name}"] = tool.description or ""

    failures = []
    for name, want in expected.items():
        got = actual.get(name)
        if got is None:
            failures.append(f"{name}: tool no longer registered (upstream renamed/removed it?)")
        elif got != want:
            failures.append(f"{name}: description mismatch\n  want: {want!r}\n  got:  {got!r}")

    if failures:
        print("Tool description check failed:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"OK: {len(expected)} tool descriptions match expected-descriptions.json")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
