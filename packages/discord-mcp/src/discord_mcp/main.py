"""Discord MCP server entry point."""

from __future__ import annotations

import logging
import sys

from fastmcp import FastMCP

from . import tools

# Send logs to stderr so they don't interfere with stdio MCP transport,
# but keep them minimal to avoid noise.
logging.basicConfig(
    level=logging.WARNING,
    format="%(levelname)s %(name)s: %(message)s",
    stream=sys.stderr,
)

mcp = FastMCP("discord")

# Register all tools
mcp.tool(tools.send_message)
mcp.tool(tools.read_messages)
mcp.tool(tools.edit_message)
mcp.tool(tools.delete_message)
mcp.tool(tools.list_servers)
mcp.tool(tools.list_channels)
mcp.tool(tools.list_server_unread)
mcp.tool(tools.find_user)
mcp.tool(tools.list_all_unread_servers)
mcp.tool(tools.list_unread_messages)
mcp.tool(tools.mark_as_read)
mcp.tool(tools.mark_server_as_read)
mcp.tool(tools.list_dms)
mcp.tool(tools.open_dm)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
