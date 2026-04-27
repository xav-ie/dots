/**
 * browser-session-reaper — close idle Chrome BrowserContexts.
 *
 * Reads the state file written by browser-session-mcp on each tool call,
 * connects to Chrome, and disposes any context whose `lastUsedAt` is older
 * than MAX_IDLE_HOURS. Prunes the state file afterwards.
 *
 * Usage: invoked from a NixOS systemd timer (every 12h by default).
 *
 * Environment:
 *   BROWSER_URL       (default: http://127.0.0.1:9222)
 *   STATE_FILE        (default: /var/lib/browser-session-mcp/state.json)
 *   MAX_IDLE_HOURS    (default: 24)
 */

import puppeteer from "puppeteer-core";
import { promises as fs } from "node:fs";
import path from "node:path";

import { resolveWsEndpoint } from "./chrome.ts";
import { DEFAULT_STATE_FILE } from "./state.ts";
import { LogWriter } from "./logs.ts";

type StateData = {
  sessions: Record<string, { lastUsedAt: string }>;
};

async function readState(file: string): Promise<StateData> {
  try {
    const raw = await fs.readFile(file, "utf8");
    const parsed = JSON.parse(raw) as Partial<StateData>;
    return { sessions: parsed.sessions ?? {} };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { sessions: {} };
    }
    throw err;
  }
}

async function writeState(file: string, state: StateData): Promise<void> {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  await fs.writeFile(tmp, JSON.stringify(state, null, 2));
  await fs.rename(tmp, file);
}

async function main(): Promise<void> {
  const browserURL = process.env.BROWSER_URL ?? "http://127.0.0.1:9222";
  const stateFile = process.env.STATE_FILE ?? DEFAULT_STATE_FILE;
  const maxIdleHours = Number(process.env.MAX_IDLE_HOURS ?? "24");

  if (!Number.isFinite(maxIdleHours) || maxIdleHours <= 0) {
    throw new Error(`Invalid MAX_IDLE_HOURS: ${process.env.MAX_IDLE_HOURS}`);
  }

  const state = await readState(stateFile);
  const cutoff = Date.now() - maxIdleHours * 60 * 60 * 1000;

  const stale: string[] = [];
  for (const [sessionId, rec] of Object.entries(state.sessions)) {
    const t = Date.parse(rec.lastUsedAt);
    if (Number.isFinite(t) && t < cutoff) stale.push(sessionId);
  }

  if (stale.length === 0) {
    process.stdout.write("No idle sessions to reap.\n");
    return;
  }

  process.stdout.write(
    `Found ${stale.length} idle session(s); connecting to Chrome...\n`,
  );

  const wsEndpoint = await resolveWsEndpoint(browserURL);
  const browser = await puppeteer.connect({
    browserWSEndpoint: wsEndpoint,
    defaultViewport: null,
  });

  const logs = new LogWriter();
  let reaped = 0;
  let alreadyGone = 0;

  try {
    for (const sessionId of stale) {
      const ctx = browser.browserContexts().find((c) => c.id === sessionId);
      if (!ctx) {
        alreadyGone += 1;
        delete state.sessions[sessionId];
        await logs.closeSession(sessionId).catch(() => undefined);
        continue;
      }
      try {
        await ctx.close();
        delete state.sessions[sessionId];
        await logs.closeSession(sessionId).catch(() => undefined);
        reaped += 1;
        process.stdout.write(`Reaped ${sessionId}\n`);
      } catch (err) {
        process.stderr.write(
          `Failed to close ${sessionId}: ${err instanceof Error ? err.message : String(err)}\n`,
        );
      }
    }
  } finally {
    await browser.disconnect().catch(() => undefined);
  }

  await writeState(stateFile, state);
  process.stdout.write(
    `Done. reaped=${reaped} already-gone=${alreadyGone} remaining=${Object.keys(state.sessions).length}\n`,
  );
}

main().catch((err: unknown) => {
  process.stderr.write(
    `Fatal: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`,
  );
  process.exit(1);
});
