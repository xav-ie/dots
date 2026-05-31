#!/usr/bin/env node
/**
 * process-top — show the processes that consumed the most CPU over a recent
 * window, using the data collected by `process-logger`.
 *
 * Usage: process-top [HOURS] [LIMIT]
 *   HOURS  look-back window in hours (default 1)
 *   LIMIT  rows to show (default 20)
 */
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

function dbPath(): string {
  const base = process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share");
  return join(base, "process-logger", "usage.db");
}

function main(): void {
  const hours = process.argv[2] ? Number(process.argv[2]) : 1;
  const limit = process.argv[3] ? Number(process.argv[3]) : 20;

  const path = dbPath();
  if (!existsSync(path)) {
    console.error(`process-top: no data yet at ${path}`);
    process.exit(1);
  }

  const db = new DatabaseSync(path);
  const rows = db
    .prepare(
      `SELECT comm, SUM(cpu_secs) AS s
       FROM usage
       WHERE ts > unixepoch() - ?
       GROUP BY comm
       ORDER BY s DESC
       LIMIT ?`,
    )
    .all(Math.round(hours * 3600), limit) as { comm: string; s: number }[];
  db.close();

  console.log(`Top ${limit} processes by CPU over the last ${hours}h:`);
  console.log(
    `${"COMMAND".padEnd(32)} ${"CPU (s)".padStart(10)} ${"CPU (min)".padStart(10)}`,
  );
  for (const { comm, s } of rows) {
    console.log(
      `${comm.slice(0, 32).padEnd(32)} ${s.toFixed(1).padStart(10)} ${(s / 60)
        .toFixed(1)
        .padStart(10)}`,
    );
  }
}

main();
