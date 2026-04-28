import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { inspect } from "node:util";

import { SessionManager } from "./sessions.ts";
import { accessibilitySnapshot } from "./snapshot.ts";
import { LogWriter, readSessionLogs, readVisits } from "./logs.ts";
import { SavedStateStore, type SavedState } from "./saved-states.ts";

// ---------------------------------------------------------------------------
// Shared response helpers
// ---------------------------------------------------------------------------

type ToolResult = {
  content: Array<
    | { type: "text"; text: string }
    | { type: "image"; data: string; mimeType: string }
  >;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

const ok = (
  text: string,
  structured?: Record<string, unknown>,
): ToolResult => ({
  content: [{ type: "text", text }],
  ...(structured ? { structuredContent: structured } : {}),
});

const errResult = (err: unknown): ToolResult => {
  // Don't rely on `instanceof Error` — bundling can make it false-negative
  // for errors thrown from inside puppeteer-core. Duck-type instead, then
  // fall back to util.inspect which handles every shape we'd see.
  let text: string;
  try {
    const e = err as { name?: unknown; message?: unknown; stack?: unknown };
    if (e && typeof e.message === "string") {
      const name =
        typeof e.name === "string" && e.name.length > 0 ? e.name : "Error";
      const stack = typeof e.stack === "string" ? `\n\n${e.stack}` : "";
      text = `${name}: ${e.message}${stack}`;
    } else if (typeof err === "string") {
      text = err;
    } else {
      text = inspect(err, { depth: 4, breakLength: 120 });
    }
  } catch (innerErr) {
    text = `<failed to format error: ${String(innerErr)}>`;
  }
  return {
    content: [{ type: "text", text }],
    isError: true,
  };
};

/**
 * Wrap a tool handler so any thrown error becomes a structured error response
 * with a human-readable message, instead of getting stringified to
 * "[object Object]" somewhere up the stack.
 */
const guard =
  <A>(fn: (args: A) => Promise<ToolResult>) =>
  async (args: A): Promise<ToolResult> => {
    try {
      return await fn(args);
    } catch (err) {
      return errResult(err);
    }
  };

const WaitUntil = z.enum([
  "load",
  "domcontentloaded",
  "networkidle0",
  "networkidle2",
]);

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

export function registerTools(
  server: McpServer,
  sessions: SessionManager,
): void {
  const logs = new LogWriter();
  const savedStates = new SavedStateStore();

  // --- session lifecycle ---

  server.registerTool(
    "open_browser_session",
    {
      description:
        "Open a new isolated browser session and return its sessionId. " +
        "Pass this id to every subsequent tool call. Sessions are full " +
        "BrowserContexts — each has its own cookies, storage, and tabs.",
      inputSchema: {
        viewport: z
          .object({
            width: z.number().int().positive(),
            height: z.number().int().positive(),
          })
          .optional()
          .describe("Initial viewport. Defaults to 1280x800."),
        useMobileUA: z
          .boolean()
          .optional()
          .describe(
            "Pretend to be Chrome on Android (Pixel 8). Sets UA + Client Hints " +
              "only — viewport, touch, and DPR are unchanged. Pass `viewport` " +
              "separately if you want a phone-sized canvas too. Default sessions " +
              "still spoof a Chrome-on-Linux desktop UA so `HeadlessChrome` " +
              "never leaks.",
          ),
      },
    },
    guard(async ({ viewport, useMobileUA }) => {
      const info = await sessions.open({ viewport, useMobileUA });
      return ok(`Opened session ${info.sessionId}`, { ...info });
    }),
  );

  server.registerTool(
    "close_browser_session",
    {
      description:
        "Close a browser session. Releases its tabs, cookies, and storage. " +
        "Idempotent — closing an unknown sessionId is not an error.",
      inputSchema: { sessionId: z.string().min(1) },
    },
    guard(async ({ sessionId }) => {
      try {
        await sessions.close(sessionId);
      } catch {
        // Idempotent — fall through to log cleanup either way.
      }
      await logs.closeSession(sessionId).catch(() => undefined);
      return ok(`Closed session ${sessionId}`);
    }),
  );

  server.registerTool(
    "list_browser_sessions",
    {
      description: "List active browser sessions on the underlying Chrome.",
      inputSchema: {},
    },
    guard(async () => {
      const list = await sessions.list();
      const body =
        list.length === 0
          ? "No active sessions."
          : list
              .map(
                (s) =>
                  `- ${s.sessionId}  pages=${s.pageCount}  url=${s.activeUrl ?? "(none)"}`,
              )
              .join("\n");
      return ok(body, { sessions: list });
    }),
  );

  // --- navigation / tabs ---

  server.registerTool(
    "navigate",
    {
      description: "Navigate the session's active page to a URL.",
      inputSchema: {
        sessionId: z.string().min(1),
        url: z.string().url(),
        waitUntil: WaitUntil.optional().describe(
          "Load event to wait for. Defaults to 'load'.",
        ),
        timeout: z.number().int().positive().optional(),
      },
    },
    guard(async ({ sessionId, url, waitUntil, timeout }) => {
      const page = await sessions.activePage(sessionId);
      await page.goto(url, { waitUntil: waitUntil ?? "load", timeout });
      return ok(`Navigated to ${page.url()}`, { url: page.url() });
    }),
  );

  server.registerTool(
    "new_page",
    {
      description:
        "Open a new tab in the session. Subsequent tool calls target this " +
        "new tab (the most recently opened one is the 'active page').",
      inputSchema: {
        sessionId: z.string().min(1),
        url: z.string().url().optional(),
      },
    },
    guard(async ({ sessionId, url }) => {
      const page = await sessions.newPage(sessionId);
      if (url) await page.goto(url);
      const pages = await sessions.pages(sessionId);
      return ok(`Opened tab #${pages.length - 1}`, {
        index: pages.length - 1,
        url: page.url(),
      });
    }),
  );

  server.registerTool(
    "list_pages",
    {
      description: "List all tabs open in the session.",
      inputSchema: { sessionId: z.string().min(1) },
    },
    guard(async ({ sessionId }) => {
      const pages = await sessions.pages(sessionId);
      const summaries = await Promise.all(
        pages.map(async (p, i) => ({
          index: i,
          url: p.url(),
          title: await p.title().catch(() => ""),
        })),
      );
      const body =
        summaries.length === 0
          ? "(no pages)"
          : summaries
              .map((s) => `${s.index}: ${s.url}  "${s.title}"`)
              .join("\n");
      return ok(body, { pages: summaries });
    }),
  );

  // --- capture ---

  server.registerTool(
    "take_screenshot",
    {
      description:
        "Capture a PNG screenshot of the session's active page. Returns " +
        "the image as base64 embedded in the response.",
      inputSchema: {
        sessionId: z.string().min(1),
        fullPage: z.boolean().optional().describe("Default false."),
      },
    },
    guard(async ({ sessionId, fullPage }) => {
      const page = await sessions.activePage(sessionId);
      const buf = await page.screenshot({
        type: "png",
        fullPage: fullPage ?? false,
        encoding: "binary",
      });
      const base64 = Buffer.from(buf as Uint8Array).toString("base64");
      return {
        content: [
          { type: "text", text: `Captured ${buf.byteLength} bytes PNG.` },
          { type: "image", data: base64, mimeType: "image/png" },
        ],
      };
    }),
  );

  server.registerTool(
    "take_snapshot",
    {
      description:
        "Capture the accessibility tree of the session's active page as " +
        "indented text. Use this for reading page structure without the " +
        "cost of a full screenshot.",
      inputSchema: { sessionId: z.string().min(1) },
    },
    guard(async ({ sessionId }) => {
      const page = await sessions.activePage(sessionId);
      const tree = await accessibilitySnapshot(page);
      return ok(tree);
    }),
  );

  // --- interact ---

  server.registerTool(
    "click",
    {
      description: "Click the first element matching the CSS selector.",
      inputSchema: {
        sessionId: z.string().min(1),
        selector: z.string().min(1),
        timeout: z.number().int().positive().optional(),
      },
    },
    guard(async ({ sessionId, selector, timeout }) => {
      const page = await sessions.activePage(sessionId);
      await page.waitForSelector(selector, { timeout: timeout ?? 5_000 });
      await page.click(selector);
      return ok(`Clicked ${selector}`);
    }),
  );

  server.registerTool(
    "type",
    {
      description:
        "Type text into the first element matching the CSS selector.",
      inputSchema: {
        sessionId: z.string().min(1),
        selector: z.string().min(1),
        text: z.string(),
        delay: z.number().int().nonnegative().optional(),
        clear: z
          .boolean()
          .optional()
          .describe("Clear the field before typing. Defaults to false."),
      },
    },
    guard(async ({ sessionId, selector, text, delay, clear }) => {
      const page = await sessions.activePage(sessionId);
      await page.waitForSelector(selector);
      if (clear) {
        await page.$eval(selector, (el: Element) => {
          if (
            el instanceof HTMLInputElement ||
            el instanceof HTMLTextAreaElement
          ) {
            el.value = "";
          }
        });
      }
      await page.type(selector, text, { delay });
      return ok(`Typed ${text.length} chars into ${selector}`);
    }),
  );

  server.registerTool(
    "wait_for",
    {
      description:
        "Wait for a CSS selector to appear, or for a specific text string " +
        "to be present anywhere in the body.",
      inputSchema: {
        sessionId: z.string().min(1),
        selector: z.string().optional(),
        text: z.string().optional(),
        timeout: z.number().int().positive().optional(),
      },
    },
    guard(async ({ sessionId, selector, text, timeout }) => {
      if (!selector && !text) {
        throw new Error("wait_for requires either `selector` or `text`.");
      }
      const page = await sessions.activePage(sessionId);
      const t = timeout ?? 10_000;
      if (selector) {
        await page.waitForSelector(selector, { timeout: t });
        return ok(`Matched selector ${selector}`);
      }
      await page.waitForFunction(
        (needle: string) => document.body?.innerText?.includes(needle) ?? false,
        { timeout: t },
        text!,
      );
      return ok(`Matched text "${text}"`);
    }),
  );

  server.registerTool(
    "evaluate",
    {
      description:
        "Run a JavaScript expression in the page and return its value. " +
        "The expression is treated as an async function body — `return ...` " +
        "explicitly, or pass a bare expression and it'll be wrapped.",
      inputSchema: {
        sessionId: z.string().min(1),
        expression: z.string().min(1),
      },
    },
    guard(async ({ sessionId, expression }) => {
      const page = await sessions.activePage(sessionId);
      // Wrap the user's code as an async IIFE and send it as a string. When
      // page.evaluate receives a string, it routes it through Runtime.evaluate
      // in the target page — runs it there, not in this Node process.
      const body = /\breturn\b/.test(expression)
        ? expression
        : `return (${expression});`;
      const result = await page.evaluate(`(async () => { ${body} })()`);
      return ok(safeStringify(result), { result: result as never });
    }),
  );

  // --- history ---

  server.registerTool(
    "list_visits",
    {
      description:
        "List page visits in this session, oldest first. A 'visit' is one " +
        "top-level navigation in one tab — bracketed by Page.frameNavigated. " +
        "Each visit has its own log file; pass `visit` to list_console_messages " +
        "or list_network_requests to scope to one.",
      inputSchema: { sessionId: z.string().min(1) },
    },
    guard(async ({ sessionId }) => {
      await sessions.findContext(sessionId);
      const visits = await readVisits(sessionId);
      const body =
        visits.length === 0
          ? "(no visits recorded)"
          : visits
              .map(
                (v) =>
                  `seq=${v.seq}  target=${v.targetId.slice(0, 8)}  ${v.openedAt}  ${v.url}`,
              )
              .join("\n");
      return ok(body, { visits });
    }),
  );

  server.registerTool(
    "list_console_messages",
    {
      description:
        "List console messages emitted by the session, across all visits or " +
        "scoped to a single visit. Returns up to `limit` most-recent entries " +
        "(default 500).",
      inputSchema: {
        sessionId: z.string().min(1),
        visit: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Optional visit seq from list_visits."),
        limit: z.number().int().positive().optional(),
      },
    },
    guard(async ({ sessionId, visit, limit }) => {
      await sessions.findContext(sessionId);
      const entries = await readSessionLogs(sessionId, {
        kind: "console",
        limit: limit ?? 500,
        visit,
      });
      const body =
        entries.length === 0
          ? "(no console messages)"
          : entries
              .map((e) => (e.kind === "console" ? `[${e.type}] ${e.text}` : ""))
              .join("\n");
      return ok(body, { messages: entries });
    }),
  );

  server.registerTool(
    "list_network_requests",
    {
      description:
        "List network requests made by the session, across all visits or " +
        "scoped to a single visit. Returns up to `limit` most-recent entries " +
        "(default 500).",
      inputSchema: {
        sessionId: z.string().min(1),
        visit: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Optional visit seq from list_visits."),
        limit: z.number().int().positive().optional(),
      },
    },
    guard(async ({ sessionId, visit, limit }) => {
      await sessions.findContext(sessionId);
      const entries = await readSessionLogs(sessionId, {
        kind: "network",
        limit: limit ?? 500,
        visit,
      });
      const body =
        entries.length === 0
          ? "(no network requests)"
          : entries
              .map((e) => {
                if (e.kind !== "network") return "";
                const status = e.failure
                  ? `FAIL:${e.failure}`
                  : e.status != null
                    ? String(e.status)
                    : "pending";
                return `${e.method} ${e.url} [${status}]`;
              })
              .join("\n");
      return ok(body, { requests: entries });
    }),
  );

  // --- saved browser states (cookies for cross-session reuse) ---

  server.registerTool(
    "save_browser_state",
    {
      description:
        "Save the session's cookies under a name so a future session can " +
        "load_browser_state with the same name and resume without logging " +
        "in again. Overwrites any existing state with this name. Cookies " +
        "are stored on disk in plaintext at /var/lib/browser-session-mcp/" +
        "states/<name>.json (mode 0600).",
      inputSchema: {
        sessionId: z.string().min(1),
        name: z
          .string()
          .min(1)
          .describe("Slug for the state. Letters, digits, '.', '_', '-' only."),
      },
    },
    guard(async ({ sessionId, name }) => {
      const ctx = await sessions.findContext(sessionId);
      const cookies = await ctx.cookies();
      const state: SavedState = {
        name,
        savedAt: new Date().toISOString(),
        cookies,
        origins: [],
      };
      await savedStates.save(state);
      return ok(`Saved ${cookies.length} cookies as "${name}".`, {
        name,
        savedAt: state.savedAt,
        cookieCount: cookies.length,
      });
    }),
  );

  server.registerTool(
    "load_browser_state",
    {
      description:
        "Load a previously saved set of cookies into this session. Merges " +
        "with any existing cookies (saved values override on domain+path+name " +
        "match). Navigate to the relevant origin afterwards to use them.",
      inputSchema: {
        sessionId: z.string().min(1),
        name: z.string().min(1),
      },
    },
    guard(async ({ sessionId, name }) => {
      const ctx = await sessions.findContext(sessionId);
      const state = await savedStates.load(name);
      if (state.cookies.length > 0) {
        await ctx.setCookie(...state.cookies);
      }
      return ok(`Loaded ${state.cookies.length} cookies from "${name}".`, {
        name,
        cookieCount: state.cookies.length,
      });
    }),
  );

  server.registerTool(
    "list_browser_states",
    {
      description:
        "List all saved browser states. Each entry is a name + savedAt + " +
        "cookieCount. Use the name with load_browser_state.",
      inputSchema: {},
    },
    guard(async () => {
      const states = await savedStates.list();
      const body =
        states.length === 0
          ? "(no saved states)"
          : states
              .map(
                (s) =>
                  `- ${s.name}  cookies=${s.cookieCount}  saved=${s.savedAt}`,
              )
              .join("\n");
      return ok(body, { states });
    }),
  );

  server.registerTool(
    "delete_browser_state",
    {
      description: "Delete a saved browser state by name.",
      inputSchema: { name: z.string().min(1) },
    },
    guard(async ({ name }) => {
      const removed = await savedStates.delete(name);
      return ok(
        removed ? `Deleted "${name}".` : `No saved state named "${name}".`,
        { name, removed },
      );
    }),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function safeStringify(value: unknown): string {
  if (value === undefined) return "undefined";
  try {
    return JSON.stringify(value, null, 2) ?? String(value);
  } catch {
    return String(value);
  }
}
