// The incremental sync engine: pull deltas from Google since each calendar's
// stored syncToken, apply them to the working arrays + cache, and keep the sidebar
// accounts/colors current. Owns launch-time cache hydration and the background
// poll. Mutations live in store.ts; this module only reconciles against Google
// (the source of truth).
import { createState } from "ags";
import GLib from "gi://GLib";
import {
  ACCOUNTS,
  ALL_DAY,
  EVENTS,
  resetCalColor,
  type AllDayEvent,
  type CalAccount,
  type CalEvent,
} from "./data";
import * as db from "./db";
import {
  byId,
  flushCache,
  reindex,
  replaceAll,
  setRev,
  type AnyEvent,
} from "./eventIndex";
import {
  fetchCalendarSync,
  googleConfigured,
  parseEventId,
  syncAccounts,
} from "./gmap";
import { accountEmails } from "./auth";
import { notify } from "./notify";
import { isTransient } from "./rest";
import { defaultCal, setAccounts, setDefaultCal } from "./state";
import { flushWrites } from "./writeQueue";

// How far before/after today to sync from Google. ±1 year covers any normal
// navigation; events outside it simply aren't fetched until the window moves.
const SYNC_WINDOW_DAYS = 365;

// A sync is in flight (drives the first-load spinner). `syncFailed` is set when a
// pass can't even list accounts — so the grid can show a retry instead of a blank
// week when the cache is still empty.
export const [syncing, setSyncing] = createState(false);
export const [syncFailed, setSyncFailed] = createState(false);

// Pristine dummy seeds, snapshotted before any Google data replaces the arrays,
// so removing the last account can revert to the not-configured demo.
const SEED_EVENTS = [...EVENTS];
const SEED_ALLDAY = [...ALL_DAY];
const SEED_ACCOUNTS = [...ACCOUNTS];

// Keep the default calendar valid and writable. New events go here, so it must
// be a calendar you can actually create events on (owner/writer). If the current
// default isn't writable (stale dummy, a removed or read-only calendar), fall
// back to the primary calendar, else any writable one. There's exactly one.
function ensureDefault(accounts: CalAccount[], primary: string | null) {
  const writable = accounts
    .flatMap((a) => a.calendars)
    .filter((c) => c.writable);
  if (writable.some((c) => c.name === defaultCal.get())) return;
  const pick = primary ?? writable[0]?.name ?? accounts[0]?.calendars[0]?.name;
  if (pick) setDefaultCal(pick);
}

// When a Google account is connected, render the cache now (events AND accounts,
// so calColor has real colors immediately — otherwise left bars/swatches show
// gray until the network sync lands) and refresh in the background. Otherwise
// keep the dummy seeds (UI demo).
if (googleConfigured()) {
  const cached = db.loadCachedEvents();
  const cachedAccounts = db.getCachedAccounts();
  replaceAll(cached.timed, cached.allDay);
  if (cachedAccounts.length) {
    ACCOUNTS.splice(0, ACCOUNTS.length, ...cachedAccounts);
    setAccounts(cachedAccounts);
  }
  resetCalColor();
  ensureDefault(ACCOUNTS, null);
  void syncNow();
} else if (db.getCachedAccounts().length) {
  // Accounts were removed in a previous session — drop the stale Google cache.
  revertToSeeds();
} else {
  reindex();
}

// Background refresh: an incremental sync every few minutes (cheap via
// syncTokens) keeps the grid current without a relaunch. syncNow() serialises
// and no-ops when nothing is connected; Calendar.tsx also syncs on window focus.
const POLL_SECONDS = 180;
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, POLL_SECONDS, () => {
  if (googleConfigured()) void syncNow();
  return GLib.SOURCE_CONTINUE;
});

// Revert the grid/sidebar/cache to the dummy demo (called when the last account
// is removed) — otherwise stale Google data lingers in memory and the cache.
export function revertToSeeds() {
  replaceAll(SEED_EVENTS, SEED_ALLDAY);
  ACCOUNTS.splice(0, ACCOUNTS.length, ...SEED_ACCOUNTS);
  resetCalColor();
  setAccounts(SEED_ACCOUNTS);
  ensureDefault(SEED_ACCOUNTS, null);
  db.cacheReplaceEvents([], []);
  db.setCachedAccounts([]);
  db.clearAllSyncTokens(); // stale tokens would desync a future re-add
  setRev((n) => n + 1);
}

// Serialise concurrent syncNow() calls: at most one sync runs at a time, and at
// most one more is queued. Rapid removals/additions therefore collapse into a
// single trailing sync rather than racing to write shared state.
let syncInflight: Promise<void> | null = null;
let syncQueued = false;

export function syncNow(): Promise<void> {
  if (syncInflight) {
    if (!syncQueued) {
      syncQueued = true;
      syncInflight = syncInflight.then(() => {
        syncQueued = false;
        return _syncNow();
      });
    }
    return syncInflight;
  }
  syncInflight = _syncNow().finally(() => {
    syncInflight = null;
  });
  return syncInflight;
}

// --- incremental cache/array mutation (sync deltas) --------------------------

// Cache changes from one sync pass are accumulated here and flushed in ONE
// batched sqlite write at the end — a per-event write spawns a sqlite3 subprocess
// (synchronous → freezes the UI), and a full first sync has hundreds of them.
let dirtyUpserts: { ev: AnyEvent; allDay: boolean }[] = [];
let dirtyDeletes: string[] = [];

// Insert-or-replace one event in the working arrays (memory now; cache batched).
// No rev bump — the caller bumps once after the whole pass. Local drafts never
// collide (their ids are "local|…", never a Google id).
function syncUpsert(ev: AnyEvent, allDay: boolean) {
  const old = byId.get(ev.id!);
  if (old) {
    const ei = EVENTS.indexOf(old as CalEvent);
    if (ei >= 0) EVENTS.splice(ei, 1);
    const ai = ALL_DAY.indexOf(old as AllDayEvent);
    if (ai >= 0) ALL_DAY.splice(ai, 1);
  }
  if (allDay) ALL_DAY.push(ev as AllDayEvent);
  else EVENTS.push(ev as CalEvent);
  byId.set(ev.id!, ev);
  dirtyUpserts.push({ ev, allDay });
}

function syncDelete(id: string) {
  const old = byId.get(id);
  if (old) {
    const ei = EVENTS.indexOf(old as CalEvent);
    if (ei >= 0) EVENTS.splice(ei, 1);
    const ai = ALL_DAY.indexOf(old as AllDayEvent);
    if (ai >= 0) ALL_DAY.splice(ai, 1);
    byId.delete(id);
  }
  dirtyDeletes.push(id);
}

// Flush accumulated sync changes to the cache in one batched write.
function flushDirty() {
  db.cacheApply(dirtyUpserts, dirtyDeletes);
  dirtyUpserts = [];
  dirtyDeletes = [];
}

// A full (windowed) sync of one calendar: drop its now-absent events, upsert the
// rest. The prefix "account|calId|" identifies the calendar's events.
function replaceCalendarSlice(
  account: string,
  calId: string,
  timed: CalEvent[],
  allDay: AllDayEvent[],
) {
  const prefix = `${account}|${calId}|`;
  const keep = new Set([...timed, ...allDay].map((e) => e.id!));
  for (const id of [...byId.keys()])
    if (id.startsWith(prefix) && !keep.has(id)) syncDelete(id);
  for (const ev of timed) syncUpsert(ev, false);
  for (const ev of allDay) syncUpsert(ev, true);
}

// Drop events belonging to calendars no longer synced (account removed or
// calendar deselected); collect their tokens to clear (deduped) so a re-add does
// a clean full sync. Tokens are flushed in one batched write by the caller.
function pruneOrphans(
  valid: Set<string>,
  tokenClears: { account: string; calId: string }[],
) {
  const cleared = new Set<string>();
  for (const id of [...byId.keys()]) {
    if (id.startsWith("local|")) continue; // keep not-yet-created drafts
    const t = parseEventId(id);
    if (!t || valid.has(`${t.account}|${t.calId}|`)) continue;
    syncDelete(id);
    const key = `${t.account}\t${t.calId}`;
    if (!cleared.has(key)) {
      cleared.add(key);
      tokenClears.push({ account: t.account, calId: t.calId });
    }
  }
}

// Incremental sync: refresh the sidebar, then per calendar apply only the changes
// since our stored syncToken (full windowed fetch the first time / after a 410).
// Local drafts and the cache are preserved across passes — no full refetch.
async function _syncNow(): Promise<void> {
  // No accounts left → clear stale Google data and show the demo seeds.
  if (!googleConfigured()) {
    revertToSeeds();
    return;
  }

  setSyncing(true);
  try {
    await _syncPass();
  } finally {
    setSyncing(false);
  }
}

async function _syncPass(): Promise<void> {
  // Replay any writes that failed while offline before pulling fresh deltas, and
  // land any coalesced optimistic cache writes so the persisted order is correct.
  await flushWrites();
  flushCache();

  let meta;
  try {
    meta = await syncAccounts();
  } catch (err) {
    setSyncFailed(true);
    notify(`Sync failed — ${err}`);
    return; // transient (e.g. network) — keep the cache rather than wiping it
  }
  if (!meta) return;
  setSyncFailed(false);

  // Sidebar accounts/colors (cheap, every pass).
  ACCOUNTS.splice(0, ACCOUNTS.length, ...meta.accounts);
  resetCalColor();
  setAccounts(meta.accounts);
  ensureDefault(meta.accounts, meta.primary);

  const today = new Date();
  const from = new Date(today);
  from.setDate(from.getDate() - SYNC_WINDOW_DAYS);
  const to = new Date(today);
  to.setDate(to.getDate() + SYNC_WINDOW_DAYS);

  // All tokens read in one query; writes/clears batched and flushed at the end.
  const tokens = db.getSyncTokens();
  const tokenSets: { account: string; calId: string; token: string }[] = [];
  const tokenClears: { account: string; calId: string }[] = [];

  for (const { account, calId, name } of meta.toSync) {
    if (!accountEmails().includes(account)) continue; // account removed mid-sync
    const token = tokens.get(`${account}\t${calId}`);
    let delta;
    let full = !token;
    try {
      delta = await fetchCalendarSync(
        account,
        calId,
        name,
        token ? { syncToken: token } : { timeMin: from, timeMax: to },
      );
      if (delta.expired) {
        tokenClears.push({ account, calId });
        delta = await fetchCalendarSync(account, calId, name, {
          timeMin: from,
          timeMax: to,
        });
        full = true;
      }
    } catch (err) {
      if (!accountEmails().includes(account)) break;
      // Transient (offline / 5xx / 429) → skip this calendar quietly; the next
      // pass retries with the same token. Only log genuine errors.
      if (!isTransient(err))
        console.error("calendar sync:", account, name, err);
      continue;
    }
    if (full) replaceCalendarSlice(account, calId, delta.timed, delta.allDay);
    else {
      for (const id of delta.deletedIds) syncDelete(id);
      for (const ev of delta.timed) syncUpsert(ev, false);
      for (const ev of delta.allDay) syncUpsert(ev, true);
    }
    if (delta.nextSyncToken)
      tokenSets.push({ account, calId, token: delta.nextSyncToken });
  }

  // Events to keep: synced calendars, plus those of accounts that failed to list
  // this pass (a transient blip) so their cached data survives until next sync.
  const valid = new Set(meta.toSync.map((s) => `${s.account}|${s.calId}|`));
  for (const a of meta.accounts)
    if (meta.failed.includes(a.account))
      for (const c of a.calendars) if (c.id) valid.add(`${a.account}|${c.id}|`);
  pruneOrphans(valid, tokenClears);
  flushDirty(); // single batched cache write for the whole pass
  db.applySyncTokens(tokenSets, tokenClears); // single batched token write
  db.setCachedAccounts(meta.accounts);
  setRev((n) => n + 1);
}
