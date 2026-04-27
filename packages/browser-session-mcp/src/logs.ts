import { promises as fs, createReadStream } from "node:fs";
import path from "node:path";
import readline from "node:readline";

export const DEFAULT_LOGS_DIR = "/var/lib/browser-session-mcp/logs";

const SEQ_PAD = 5; // 99999 visits per session — plenty.

export type ConsoleEntry = {
  readonly t: string;
  readonly kind: "console";
  readonly type: string;
  readonly text: string;
};

export type NetworkEntry = {
  readonly t: string;
  readonly kind: "network";
  readonly method: string;
  readonly url: string;
  readonly status: number | null;
  readonly failure?: string;
};

export type VisitHeader = {
  readonly kind: "visit";
  readonly seq: number;
  readonly targetId: string;
  readonly url: string;
  readonly openedAt: string;
};

export type LogEntry = ConsoleEntry | NetworkEntry;

const sanitize = (s: string): string => s.replace(/[^A-Za-z0-9_-]/g, "_");
const pad = (n: number): string => String(n).padStart(SEQ_PAD, "0");

const sessionDir = (logsDir: string, sessionId: string): string =>
  path.join(logsDir, sanitize(sessionId));

const visitFile = (
  logsDir: string,
  sessionId: string,
  seq: number,
  targetId: string,
): string =>
  path.join(
    sessionDir(logsDir, sessionId),
    `${pad(seq)}-${sanitize(targetId)}.ndjson`,
  );

const seqFromFilename = (name: string): number => {
  const head = name.split("-", 1)[0];
  return Number.parseInt(head ?? "", 10);
};

/**
 * Per-visit NDJSON writer.
 *
 * Layout:
 *   <logsDir>/<sessionId>/<seq>-<targetId>.ndjson
 *
 * Each file starts with a {"kind":"visit",...} header. Subsequent lines are
 * console + network events. A new file is opened on every top-level
 * navigation (driven by listener.ts). The session folder is rm'd on close.
 */
export class LogWriter {
  private readonly logsDir: string;
  // In-memory next-seq cache per session, lazily populated by reading the
  // existing folder on first call so we resume correctly after a listener
  // restart.
  private readonly nextSeqs = new Map<string, number>();

  constructor(logsDir?: string) {
    this.logsDir = logsDir ?? process.env.LOGS_DIR ?? DEFAULT_LOGS_DIR;
  }

  private async resolveNextSeq(sessionId: string): Promise<number> {
    const cached = this.nextSeqs.get(sessionId);
    if (cached !== undefined) return cached;
    const dir = sessionDir(this.logsDir, sessionId);
    const files = await fs.readdir(dir).catch(() => [] as string[]);
    let max = 0;
    for (const f of files) {
      const s = seqFromFilename(f);
      if (Number.isFinite(s) && s > max) max = s;
    }
    return max + 1;
  }

  async openVisit(
    sessionId: string,
    targetId: string,
    url: string,
  ): Promise<number> {
    const dir = sessionDir(this.logsDir, sessionId);
    await fs.mkdir(dir, { recursive: true });
    const seq = await this.resolveNextSeq(sessionId);
    this.nextSeqs.set(sessionId, seq + 1);
    const header: VisitHeader = {
      kind: "visit",
      seq,
      targetId,
      url,
      openedAt: new Date().toISOString(),
    };
    await fs.appendFile(
      visitFile(this.logsDir, sessionId, seq, targetId),
      JSON.stringify(header) + "\n",
    );
    return seq;
  }

  async append(
    sessionId: string,
    seq: number,
    targetId: string,
    entry: LogEntry,
  ): Promise<void> {
    await fs.appendFile(
      visitFile(this.logsDir, sessionId, seq, targetId),
      JSON.stringify(entry) + "\n",
    );
  }

  async closeSession(sessionId: string): Promise<void> {
    this.nextSeqs.delete(sessionId);
    await fs
      .rm(sessionDir(this.logsDir, sessionId), { recursive: true, force: true })
      .catch(() => undefined);
  }
}

/**
 * Read events for a session. If `visit` is given, only that visit's events;
 * otherwise events from every visit, ordered by seq. Limit is applied across
 * the merged stream (most recent kept).
 */
export async function readSessionLogs(
  sessionId: string,
  opts: {
    logsDir?: string;
    kind?: "console" | "network";
    limit?: number;
    visit?: number;
  } = {},
): Promise<LogEntry[]> {
  const dir = sessionDir(
    opts.logsDir ?? process.env.LOGS_DIR ?? DEFAULT_LOGS_DIR,
    sessionId,
  );
  const files = await orderedFiles(dir, opts.visit);

  const out: LogEntry[] = [];
  for (const f of files) {
    const stream = createReadStream(path.join(dir, f), { encoding: "utf8" });
    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    try {
      for await (const line of rl) {
        if (!line) continue;
        let entry: LogEntry | VisitHeader;
        try {
          entry = JSON.parse(line) as LogEntry | VisitHeader;
        } catch {
          continue;
        }
        if (entry.kind === "visit") continue; // header line
        if (opts.kind && entry.kind !== opts.kind) continue;
        out.push(entry);
      }
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
    }
  }

  if (opts.limit && out.length > opts.limit) {
    return out.slice(-opts.limit);
  }
  return out;
}

/**
 * Read just the visit headers for a session, ordered by seq. Cheap — one
 * line read per file.
 */
export async function readVisits(
  sessionId: string,
  logsDir?: string,
): Promise<VisitHeader[]> {
  const dir = sessionDir(
    logsDir ?? process.env.LOGS_DIR ?? DEFAULT_LOGS_DIR,
    sessionId,
  );
  const files = await orderedFiles(dir);

  const visits: VisitHeader[] = [];
  for (const f of files) {
    const stream = createReadStream(path.join(dir, f), { encoding: "utf8" });
    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    try {
      for await (const line of rl) {
        if (!line) continue;
        try {
          const entry = JSON.parse(line) as { kind?: string };
          if (entry.kind === "visit") visits.push(entry as VisitHeader);
        } catch {
          // ignore
        }
        rl.close();
        break;
      }
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
    }
  }

  return visits;
}

async function orderedFiles(dir: string, visit?: number): Promise<string[]> {
  let files: string[];
  try {
    files = await fs.readdir(dir);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
  files = files.filter((f) => f.endsWith(".ndjson"));
  if (visit !== undefined) {
    files = files.filter((f) => seqFromFilename(f) === visit);
  }
  // Filenames are zero-padded so lexical sort matches numeric.
  files.sort();
  return files;
}
