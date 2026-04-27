/**
 * browser-session-mcp — MCP server over stdio.
 *
 * Connects (lazily) to a persistent Chrome via the DevTools Protocol, hands
 * out isolated BrowserContexts per caller-managed sessionId.
 *
 * Environment:
 *   BROWSER_URL   (required)  DevTools HTTP endpoint, e.g. http://chrome:9222
 *
 * The Chrome connection is deferred until the first tool call. Boot succeeds
 * even if Chrome is down — failures show up at tool-call time instead of
 * crashing the subprocess and (via mcp-proxy) cascading into the host.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { getBrowser, closeBrowser } from "./chrome.ts";
import { SessionManager } from "./sessions.ts";
import { StateStore } from "./state.ts";
import { registerTools } from "./tools.ts";

async function main(): Promise<void> {
  const browserURL = process.env.BROWSER_URL;
  if (!browserURL) {
    process.stderr.write("BROWSER_URL is required.\n");
    process.exit(1);
  }

  const state = new StateStore();
  await state.load();

  const sessions = new SessionManager(() => getBrowser(browserURL), state);

  const server = new McpServer(
    { name: "browser-session-mcp", version: "0.1.0" },
    { capabilities: { tools: {} } },
  );
  registerTools(server, sessions);

  const transport = new StdioServerTransport();
  await server.connect(transport);

  const shutdown = async () => {
    await state.flush().catch(() => undefined);
    await server.close().catch(() => undefined);
    await closeBrowser().catch(() => undefined);
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  process.stdin.on("end", shutdown);
  process.stdin.on("close", shutdown);
}

main().catch((err: unknown) => {
  process.stderr.write(
    `Fatal: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`,
  );
  process.exit(1);
});
