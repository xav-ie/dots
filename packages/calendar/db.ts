// Local SQLite *cache* of Google Calendar, via the `sqlite3` CLI (on PATH through
// the Nix wrapper). Google is the source of truth; this is just a materialized
// view so the grid can render instantly on launch before the network refresh
// lands. Events are stored as whole JSON payloads keyed by id; the connected
// accounts (for the sidebar) are cached as a settings blob. The `settings` table
// also holds app preferences (default calendar, gutter timezones).
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import type { AllDayEvent, CalAccount, CalEvent } from "./data";

const DIR = `${GLib.get_user_data_dir()}/calendar`;
const DB = `${DIR}/calendar.db`;

// Run SQL by piping it to sqlite3 over stdin (NOT as an argv argument): a full
// cache write is far larger than ARG_MAX, so passing it on the command line
// fails with "Argument list too long".
function run(sql: string, json = false, quiet = false): string {
  try {
    GLib.mkdir_with_parents(DIR, 0o755);
    const argv = json ? ["sqlite3", "-json", DB] : ["sqlite3", DB];
    const proc = Gio.Subprocess.new(
      argv,
      Gio.SubprocessFlags.STDIN_PIPE |
        Gio.SubprocessFlags.STDOUT_PIPE |
        Gio.SubprocessFlags.STDERR_PIPE,
    );
    const [, out, err] = proc.communicate_utf8(sql, null);
    if (proc.get_exit_status() !== 0) {
      if (!quiet) console.error("calendar db:", err || "nonzero exit");
      return "";
    }
    return out ?? "";
  } catch (e) {
    if (!quiet) console.error("calendar db: spawn failed", e);
    return "";
  }
}

const esc = (s: string) => s.replace(/'/g, "''");

export function init() {
  // busy_timeout guards against a transient lock if two instances race on load.
  // Purge any stale local drafts: an uncreated "local|…" event must never
  // survive a session (a crash/close mid-draft would otherwise resurrect it as a
  // phantom next launch, sitting beside the real event once it's created).
  run(
    "PRAGMA busy_timeout=2000;" +
      "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);" +
      "CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, payload TEXT, allDay INTEGER);" +
      "DELETE FROM events WHERE id LIKE 'local|%';",
  );
}

// --- app settings (preferences) ---------------------------------------------

export function getSetting(key: string): string {
  return run(`SELECT value FROM settings WHERE key='${esc(key)}';`).trim();
}

export function setSetting(key: string, value: string) {
  run(
    `INSERT INTO settings (key, value) VALUES ('${esc(key)}', '${esc(value)}') ` +
      `ON CONFLICT(key) DO UPDATE SET value='${esc(value)}';`,
  );
}

// --- per-calendar sync tokens (incremental sync) -----------------------------

// Google's nextSyncToken per (account, calendar), stored in settings. The tab
// separator can't appear in an email or calendar id, so the key is unambiguous.
const tokKey = (account: string, calId: string) =>
  `synctok:${account}\t${calId}`;

export const clearAllSyncTokens = () =>
  run(`DELETE FROM settings WHERE key LIKE 'synctok:%';`);

// All tokens in ONE query, keyed "account\tcalId" — so a sync pass reads every
// token with a single sqlite spawn instead of one per calendar (which froze the
// UI). applySyncTokens writes/clears the pass's tokens in one transaction.
export function getSyncTokens(): Map<string, string> {
  const out = run(
    "SELECT key, value FROM settings WHERE key LIKE 'synctok:%';",
    true,
  ).trim();
  const map = new Map<string, string>();
  if (!out) return map;
  try {
    for (const r of JSON.parse(out) as { key: string; value: string }[])
      map.set(r.key.slice("synctok:".length), r.value);
  } catch {
    // corrupt row → ignore; a missing token just triggers a full resync
  }
  return map;
}

export function applySyncTokens(
  sets: { account: string; calId: string; token: string }[],
  clears: { account: string; calId: string }[],
) {
  if (!sets.length && !clears.length) return;
  let sql = "BEGIN;";
  for (const c of clears)
    sql += ` DELETE FROM settings WHERE key='${esc(tokKey(c.account, c.calId))}';`;
  for (const s of sets) {
    const k = esc(tokKey(s.account, s.calId));
    const v = esc(s.token);
    sql +=
      ` INSERT INTO settings (key, value) VALUES ('${k}', '${v}') ` +
      `ON CONFLICT(key) DO UPDATE SET value='${v}';`;
  }
  sql += " COMMIT;";
  run(sql);
}

// --- event cache -------------------------------------------------------------

interface EventRow {
  id: string;
  payload: string;
  allDay: number;
}

// Replace the whole event cache atomically (called after a successful sync).
export function cacheReplaceEvents(timed: CalEvent[], allDay: AllDayEvent[]) {
  const rows = [
    ...timed.map((e) => `('${esc(e.id!)}', '${esc(JSON.stringify(e))}', 0)`),
    ...allDay.map((e) => `('${esc(e.id!)}', '${esc(JSON.stringify(e))}', 1)`),
  ];
  let sql = "BEGIN; DELETE FROM events;";
  // sqlite caps SQL statement length; chunk the inserts to stay well under it.
  for (let i = 0; i < rows.length; i += 256) {
    const chunk = rows.slice(i, i + 256).join(",");
    if (chunk)
      sql += ` INSERT INTO events (id, payload, allDay) VALUES ${chunk};`;
  }
  sql += " COMMIT;";
  run(sql);
}

// Apply a batch of upserts + deletes in ONE sqlite invocation. The incremental
// sync produces many per-event changes; doing them individually spawns a sqlite3
// subprocess each (synchronous → freezes the UI), so they're batched here.
export function cacheApply(
  upserts: { ev: CalEvent | AllDayEvent; allDay: boolean }[],
  deletedIds: string[],
) {
  if (!upserts.length && !deletedIds.length) return;
  let sql = "BEGIN;";
  for (let i = 0; i < deletedIds.length; i += 256) {
    const ids = deletedIds
      .slice(i, i + 256)
      .map((id) => `'${esc(id)}'`)
      .join(",");
    if (ids) sql += ` DELETE FROM events WHERE id IN (${ids});`;
  }
  const rows = upserts.map(
    (u) =>
      `('${esc(u.ev.id!)}', '${esc(JSON.stringify(u.ev))}', ${u.allDay ? 1 : 0})`,
  );
  for (let i = 0; i < rows.length; i += 256) {
    const chunk = rows.slice(i, i + 256).join(",");
    if (chunk)
      sql += ` INSERT OR REPLACE INTO events (id, payload, allDay) VALUES ${chunk};`;
  }
  sql += " COMMIT;";
  run(sql);
}

// Upsert a single cached event (local optimistic edit / Phase C write-back).
export function cacheUpsertEvent(ev: CalEvent | AllDayEvent, allDay: boolean) {
  const v = `'${esc(ev.id!)}', '${esc(JSON.stringify(ev))}', ${allDay ? 1 : 0}`;
  run(
    `INSERT INTO events (id, payload, allDay) VALUES (${v}) ` +
      `ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, allDay=excluded.allDay;`,
  );
}

export function cacheDeleteEvent(id: string) {
  run(`DELETE FROM events WHERE id='${esc(id)}';`);
}

export function loadCachedEvents(): {
  timed: CalEvent[];
  allDay: AllDayEvent[];
} {
  const out = run("SELECT * FROM events;", true).trim();
  const timed: CalEvent[] = [];
  const allDay: AllDayEvent[] = [];
  if (!out) return { timed, allDay };
  try {
    for (const r of JSON.parse(out) as EventRow[]) {
      const ev = JSON.parse(r.payload);
      if (r.allDay) allDay.push(ev as AllDayEvent);
      else timed.push(ev as CalEvent);
    }
  } catch {
    // corrupt cache → treat as empty; next sync rebuilds it
  }
  return { timed, allDay };
}

// --- cached account list (sidebar, before the network refresh) ---------------

export function setCachedAccounts(accounts: CalAccount[]) {
  setSetting("accounts", JSON.stringify(accounts));
}

export function getCachedAccounts(): CalAccount[] {
  const raw = getSetting("accounts");
  if (!raw) return [];
  try {
    return JSON.parse(raw) as CalAccount[];
  } catch {
    return [];
  }
}
