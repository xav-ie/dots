import { promises as fs } from "node:fs";
import path from "node:path";
import type { Cookie } from "puppeteer-core";

export const DEFAULT_STATES_DIR = "/var/lib/browser-session-mcp/states";

export type SavedState = {
  readonly name: string;
  readonly savedAt: string;
  readonly cookies: readonly Cookie[];
  /**
   * Per-origin storage. Empty in v1 (cookies-only). Reserved for future
   * localStorage / sessionStorage support so loaders can be forward-compatible.
   */
  readonly origins: readonly OriginStorage[];
};

export type OriginStorage = {
  readonly origin: string;
  readonly localStorage?: ReadonlyArray<{
    readonly name: string;
    readonly value: string;
  }>;
  readonly sessionStorage?: ReadonlyArray<{
    readonly name: string;
    readonly value: string;
  }>;
};

export type StateSummary = {
  readonly name: string;
  readonly savedAt: string;
  readonly cookieCount: number;
};

const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export class InvalidStateNameError extends Error {
  constructor(name: string) {
    super(
      `Invalid state name: ${JSON.stringify(name)}. Use letters, digits, '.', '_', '-'.`,
    );
    this.name = "InvalidStateNameError";
  }
}

export class StateNotFoundError extends Error {
  constructor(name: string) {
    super(`No saved browser state named ${JSON.stringify(name)}.`);
    this.name = "StateNotFoundError";
  }
}

const validateName = (name: string): void => {
  if (!NAME_RE.test(name)) throw new InvalidStateNameError(name);
};

const fileFor = (dir: string, name: string): string =>
  path.join(dir, `${name}.json`);

/**
 * Atomic JSON store for named browser states (cookies-only in v1). Written
 * with 0600 file mode so other users on the host can't read auth tokens.
 */
export class SavedStateStore {
  constructor(
    private readonly dir: string = process.env.STATES_DIR ?? DEFAULT_STATES_DIR,
  ) {}

  async save(state: SavedState): Promise<void> {
    validateName(state.name);
    await fs.mkdir(this.dir, { recursive: true, mode: 0o700 });
    const file = fileFor(this.dir, state.name);
    const tmp = `${file}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(state, null, 2), { mode: 0o600 });
    await fs.rename(tmp, file);
  }

  async load(name: string): Promise<SavedState> {
    validateName(name);
    const file = fileFor(this.dir, name);
    let raw: string;
    try {
      raw = await fs.readFile(file, "utf8");
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        throw new StateNotFoundError(name);
      }
      throw err;
    }
    return JSON.parse(raw) as SavedState;
  }

  async list(): Promise<StateSummary[]> {
    let files: string[];
    try {
      files = await fs.readdir(this.dir);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw err;
    }
    const out: StateSummary[] = [];
    for (const f of files) {
      if (!f.endsWith(".json")) continue;
      const name = f.slice(0, -5);
      try {
        const raw = await fs.readFile(path.join(this.dir, f), "utf8");
        const parsed = JSON.parse(raw) as SavedState;
        out.push({
          name: parsed.name ?? name,
          savedAt: parsed.savedAt ?? "",
          cookieCount: parsed.cookies?.length ?? 0,
        });
      } catch {
        // Corrupt file — skip rather than fail the whole listing.
      }
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
  }

  async delete(name: string): Promise<boolean> {
    validateName(name);
    try {
      await fs.unlink(fileFor(this.dir, name));
      return true;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return false;
      throw err;
    }
  }
}
