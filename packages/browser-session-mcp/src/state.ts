import { promises as fs } from "node:fs";
import path from "node:path";

export const DEFAULT_STATE_FILE = "/var/lib/browser-session-mcp/state.json";

export type SessionRecord = {
  readonly lastUsedAt: string;
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
    this.state.sessions[sessionId] = { lastUsedAt: new Date().toISOString() };
    this.markDirty();
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
