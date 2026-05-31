#!/usr/bin/env node
/**
 * process-logger — sample per-process cumulative CPU time and record the
 * per-interval delta to SQLite.
 *
 * Runs on a timer (every few minutes). Each run:
 *   1. snapshots every process's cumulative CPU seconds via `ps`
 *   2. diffs against the previous snapshot to get CPU used *this interval*
 *   3. appends those deltas to SQLite (one row per process per interval)
 *   4. prunes rows older than RETENTION_DAYS
 *
 * Answers a question btop/top cannot: "what used the most CPU over the last
 * hour/day?" Query it with `process-top`, or directly:
 *
 *   SELECT comm, SUM(cpu_secs) AS s FROM usage
 *   WHERE ts > unixepoch() - 3600
 *   GROUP BY comm ORDER BY s DESC LIMIT 20;
 */
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const RETENTION_DAYS = 30;

function dbPath(): string {
  const base = process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share");
  return join(base, "process-logger", "usage.db");
}

/** Parse a ps TIME field ('MM:SS.ss', 'HH:MM:SS', 'D-HH:MM:SS') into seconds. */
function parseCpuTime(s: string): number {
  let days = 0;
  const dash = s.indexOf("-");
  if (dash !== -1) {
    days = Number(s.slice(0, dash));
    s = s.slice(dash + 1);
  }
  let secs = 0;
  for (const part of s.split(":")) secs = secs * 60 + Number(part);
  return days * 86400 + secs;
}

interface Proc {
  cpu: number; // cumulative CPU seconds since the process started
  comm: string;
}

/** Snapshot {pid -> {cpu, comm}} for every running process. */
function snapshot(): Map<number, Proc> {
  const out = execFileSync("ps", ["-axo", "pid=,time=,comm="], {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  const procs = new Map<number, Proc>();
  for (const raw of out.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    // `time` has no spaces, so the first two tokens are clean and the
    // remainder (which may contain spaces) is the command.
    const m = line.match(/^(\d+)\s+(\S+)\s+(.*)$/);
    if (!m) continue;
    procs.set(Number(m[1]), { cpu: parseCpuTime(m[2]), comm: m[3] });
  }
  return procs;
}

interface Delta {
  pid: number;
  comm: string;
  cpuSecs: number;
}

/**
 * CPU seconds consumed by each process since the previous snapshot.
 *
 * @param prev pid -> cumulative cpu seconds from the last run (empty first run)
 * @param curr pid -> {cpu, comm} from this run
 * @returns one entry per process that used CPU this interval
 *          (callers drop cpuSecs <= 0 before storing)
 */
function computeDeltas(
  prev: Map<number, number>,
  curr: Map<number, Proc>,
): Delta[] {
  const deltas: Delta[] = [];
  for (const [pid, { cpu, comm }] of curr) {
    const before = prev.get(pid);
    // New PID (no baseline) or PID reuse / counter reset (cumulative time went
    // backwards): skip this round and let the next interval measure cleanly
    // from the baseline we store now. Counting cpu here would attribute CPU
    // burned before we were watching, spiking the first bucket.
    if (before === undefined || cpu < before) continue;
    deltas.push({ pid, comm, cpuSecs: cpu - before });
  }
  return deltas;
}

function main(): void {
  const path = dbPath();
  mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS usage (
      ts       INTEGER NOT NULL,
      pid      INTEGER NOT NULL,
      comm     TEXT    NOT NULL,
      cpu_secs REAL    NOT NULL
    );
    CREATE INDEX IF NOT EXISTS usage_ts   ON usage(ts);
    CREATE INDEX IF NOT EXISTS usage_comm ON usage(comm);
    CREATE TABLE IF NOT EXISTS snapshot (
      pid     INTEGER PRIMARY KEY,
      cputime REAL NOT NULL
    );
  `);

  const prev = new Map<number, number>();
  const prevRows = db.prepare("SELECT pid, cputime FROM snapshot").all() as {
    pid: number;
    cputime: number;
  }[];
  for (const row of prevRows) prev.set(row.pid, row.cputime);

  const curr = snapshot();
  const now = Math.floor(Date.now() / 1000);

  const insert = db.prepare(
    "INSERT INTO usage (ts, pid, comm, cpu_secs) VALUES (?, ?, ?, ?)",
  );
  for (const d of computeDeltas(prev, curr)) {
    if (d.cpuSecs > 0) insert.run(now, d.pid, d.comm, d.cpuSecs);
  }

  // Replace the stored snapshot with this run's cumulative readings.
  db.exec("DELETE FROM snapshot");
  const snap = db.prepare("INSERT INTO snapshot (pid, cputime) VALUES (?, ?)");
  for (const [pid, p] of curr) snap.run(pid, p.cpu);

  // Rolling retention window.
  db.prepare("DELETE FROM usage WHERE ts < ?").run(
    now - RETENTION_DAYS * 86400,
  );
  db.close();
}

main();
