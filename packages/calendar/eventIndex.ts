// The in-memory event index and the cache/target primitives that the mutation
// API (store.ts), the sync engine (sync.ts) and the offline write queue
// (writeQueue.ts) all build on. Google is the source of truth; the SQLite DB is
// a cache. The arrays the views render (EVENTS / ALL_DAY in data.ts) are mutated
// in place so eventsOn/allDayOn reflect changes; `rev` is bumped to re-lay-out
// the grid.
import { createState } from "ags";
import GLib from "gi://GLib";
import {
  ACCOUNTS,
  ALL_DAY,
  EVENTS,
  type AllDayEvent,
  type CalAccount,
  type CalEvent,
} from "./data";
import * as db from "./db";
import { parseEventId } from "./gmap";

export type AnyEvent = CalEvent | AllDayEvent;

db.init();

// Id → live event object. The single lookup the views/editor resolve through, so
// they always touch the object the latest sync produced (not a stale copy).
export const byId = new Map<string, AnyEvent>();
export function reindex() {
  byId.clear();
  for (const e of [...EVENTS, ...ALL_DAY]) byId.set(e.id!, e);
}

// Bumped when an edit changes the grid (so columns re-render).
export const [rev, setRev] = createState(0);

// Swap the working arrays' contents in place (other modules hold references).
export function replaceAll(timed: CalEvent[], allDay: AllDayEvent[]) {
  EVENTS.splice(0, EVENTS.length, ...timed);
  ALL_DAY.splice(0, ALL_DAY.length, ...allDay);
  reindex();
}

export const isAllDay = (e: AnyEvent): boolean =>
  ALL_DAY.includes(e as AllDayEvent) || (e as CalEvent).allDay === true;

// Optimistic cache writes are coalesced and flushed on idle in ONE batched
// sqlite write: a per-edit synchronous sqlite3 spawn janks the UI on drags and
// rapid typing. The sync engine calls flushCache() before applying its own
// deltas so the persisted order matches memory. Pending writes are an optimistic
// mirror of in-memory state (which re-syncs from Google), so dropping them on a
// crash/exit is safe — the next full sync reconciles.
const pendingUpserts = new Map<string, { ev: AnyEvent; allDay: boolean }>();
const pendingDeletes = new Set<string>();
let flushScheduled = false;

function scheduleFlush() {
  if (flushScheduled) return;
  flushScheduled = true;
  GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
    flushCache();
    return GLib.SOURCE_REMOVE;
  });
}

// Flush queued optimistic cache writes now (also called by the sync engine).
export function flushCache() {
  flushScheduled = false;
  if (!pendingUpserts.size && !pendingDeletes.size) return;
  const upserts = [...pendingUpserts.values()];
  const deletes = [...pendingDeletes];
  pendingUpserts.clear();
  pendingDeletes.clear();
  db.cacheApply(upserts, deletes);
}

// Persist an in-memory event to the cache (optimistic; also pushed to Google).
// Skip not-yet-created drafts ("local|…") — they live in memory only; persisting
// them resurrects phantoms next launch if the session ends before they're created.
export function recache(e: AnyEvent) {
  if (e.id?.startsWith("local|")) return;
  pendingDeletes.delete(e.id!);
  pendingUpserts.set(e.id!, { ev: e, allDay: isAllDay(e) });
  scheduleFlush();
}

// Queue a cached-event delete (coalesced with recache writes).
export function decache(id: string) {
  pendingUpserts.delete(id);
  pendingDeletes.add(id);
  scheduleFlush();
}

// A synced event id → its Google target, or null for local/dummy events.
export function googleTarget(
  id: string | undefined,
): { account: string; calId: string; gid: string } | null {
  if (!id) return null;
  const t = parseEventId(id);
  return t && t.account !== "local" ? t : null;
}

// The Google account + calendar id for a calendar name (real calendars only).
// `prefer` resolves within that account first — calendar names can collide
// across accounts, and a move stores only the name, so we keep it in the event's
// own account when possible.
export function calTarget(
  calName: string,
  prefer?: string,
): { account: string; calId: string } | null {
  const find = (a: CalAccount) => {
    const c = a.calendars.find((c) => c.name === calName && c.id);
    return c ? { account: a.account, calId: c.id! } : null;
  };
  if (prefer) {
    const a = ACCOUNTS.find((a) => a.account === prefer);
    const r = a && find(a);
    if (r) return r;
  }
  for (const a of ACCOUNTS) {
    const r = find(a);
    if (r) return r;
  }
  return null;
}

// Re-key an event after Google assigns/changes its id (create, calendar move).
export function reassignId(e: AnyEvent, newId: string) {
  byId.delete(e.id!);
  decache(e.id!);
  e.id = newId;
  byId.set(newId, e);
  recache(e);
}
