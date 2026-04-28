import { promises as fs } from "node:fs";
import path from "node:path";
import type { Protocol } from "devtools-protocol";

import type { UAOverride } from "./userAgent.ts";

export const DEFAULT_STATE_FILE = "/var/lib/browser-session-mcp/state.json";

export type SessionRecord = {
  readonly lastUsedAt: string;
  readonly userAgent?: string;
  readonly userAgentMetadata?: Protocol.Emulation.UserAgentMetadata;
};

type StateData = {
  sessions: Record<string, SessionRecord>;
};

const empty = (): StateData => ({ sessions: {} });

/**
 * JSON file recording per-session metadata. Touched on every per-session
 * tool call so the reaper can find and close idle BrowserContexts.
 *
 * Writes are debounced (1s) and atomic (write to .tmp + rename) so frequent
 * tool calls don't thrash the filesystem and a crash mid-write doesn't
 * leave the file truncated.
 */
export class StateStore {
  private readonly file: string;
  private state: StateData = empty();
  private loaded = false;
  private dirty = false;
  private flushTimer: NodeJS.Timeout | undefined;

  constructor(file?: string) {
    this.file = file ?? process.env.STATE_FILE ?? DEFAULT_STATE_FILE;
  }

  async load(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await fs.readFile(this.file, "utf8");
      const parsed = JSON.parse(raw) as Partial<StateData>;
      this.state = { sessions: parsed.sessions ?? {} };
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
        process.stderr.write(
          `[state] failed to load ${this.file}: ${String(err)}\n`,
        );
      }
      this.state = empty();
    }
    this.loaded = true;
  }

  touch(sessionId: string): void {
    const existing = this.state.sessions[sessionId];
    this.state.sessions[sessionId] = {
      ...existing,
      lastUsedAt: new Date().toISOString(),
    };
    this.markDirty();
  }

  setUserAgentOverride(sessionId: string, override: UAOverride): void {
    const existing = this.state.sessions[sessionId];
    this.state.sessions[sessionId] = {
      lastUsedAt: existing?.lastUsedAt ?? new Date().toISOString(),
      userAgent: override.userAgent,
      userAgentMetadata: override.userAgentMetadata,
    };
    this.markDirty();
  }

  getUserAgentOverride(sessionId: string): UAOverride | undefined {
    const rec = this.state.sessions[sessionId];
    if (!rec?.userAgent || !rec.userAgentMetadata) return undefined;
    return {
      userAgent: rec.userAgent,
      userAgentMetadata: rec.userAgentMetadata,
    };
  }

  forget(sessionId: string): void {
    if (sessionId in this.state.sessions) {
      delete this.state.sessions[sessionId];
      this.markDirty();
    }
  }

  list(): Array<{ sessionId: string } & SessionRecord> {
    return Object.entries(this.state.sessions).map(([sessionId, rec]) => ({
      sessionId,
      ...rec,
    }));
  }

  private markDirty(): void {
    this.dirty = true;
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined;
      void this.flush();
    }, 1000);
    this.flushTimer.unref?.();
  }

  async flush(): Promise<void> {
    if (!this.dirty) return;
    this.dirty = false;
    try {
      await fs.mkdir(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.tmp`;
      await fs.writeFile(tmp, JSON.stringify(this.state, null, 2));
      await fs.rename(tmp, this.file);
    } catch (err) {
      // Don't crash the MCP if state write fails — just retry on next event.
      this.dirty = true;
      process.stderr.write(
        `[state] failed to flush ${this.file}: ${String(err)}\n`,
      );
    }
  }
}
