// Optimistic write path to Google: PATCH a synced event's fields, serialise rapid
// edits to the same event, and replay writes that failed while offline. Kept apart
// from the mutation API (store.ts) and the sync engine (sync.ts), which both drive
// it. Builds on the cache/target primitives in eventIndex.
import type { CalEvent } from "./data";
import { googleTarget, recache } from "./eventIndex";
import { notify } from "./notify";
import { getEvent, isTransient, patchEvent } from "./rest";

// PATCHes that failed transiently keep their optimistic change and retry via this
// queue, flushed on the next sync (poll / focus). In-memory only — a restart drops
// the queue and the next full sync reconciles — and limited to field PATCHes;
// creates/moves still revert on hard failure.
const writeQueue: Array<() => Promise<void>> = [];
let flushing = false;
let offline = false;

export function enqueueWrite(fn: () => Promise<void>) {
  if (!offline) {
    offline = true;
    notify("Offline — changes will sync when reconnected", "info");
  }
  writeQueue.push(fn);
}

export async function flushWrites(): Promise<void> {
  if (flushing || !writeQueue.length) return;
  flushing = true;
  for (const fn of writeQueue.splice(0)) {
    try {
      await fn(); // resolved → done (succeeded or permanently reverted)
    } catch {
      writeQueue.push(fn); // still transient → keep for the next flush
    }
  }
  flushing = false;
  if (offline && !writeQueue.length) {
    offline = false;
    notify("Back online — changes synced", "info");
  }
}

// Serialise PATCHes per event: at most one in-flight + one pending. The pending
// slot always holds the latest body/revert pair, so rapid edits to the same
// event collapse into two sequential requests instead of N racing ones.
const patchInflight = new Map<string, Promise<void>>();
const patchPending = new Map<
  string,
  { body: object; revert: () => void; sendUpdates: boolean }
>();

// One PATCH attempt: If-Match with the event's etag, refreshing once on 412.
// Resolves on success OR a permanent rejection (which it reverts); throws only on
// a transient error, so the offline queue can retry without losing the edit.
async function patchOnce(
  ev: CalEvent,
  t: { account: string; calId: string; gid: string },
  b: object,
  su: boolean,
  revert: () => void,
): Promise<void> {
  const send = (etag?: string) =>
    patchEvent(t.account, t.calId, t.gid, b, su, etag);
  try {
    let etag: string | undefined;
    try {
      etag = await send(ev.etag);
    } catch (err) {
      // 412: our etag is stale (own prior write or another device) → refresh and
      // re-apply our field on top of the current version.
      if (!/→ 412\b/.test(String(err))) throw err;
      const fresh = await getEvent(t.account, t.calId, t.gid);
      ev.etag = fresh.etag;
      etag = await send(fresh.etag);
    }
    if (etag) {
      ev.etag = etag;
      recache(ev);
    }
  } catch (err) {
    if (isTransient(err)) throw err; // keep optimistic change; queue a retry
    notify(`Couldn't save change — ${err}`);
    revert();
  }
}

// PATCH the given fields of a synced event (no-op for local/dummy events). A
// permanent rejection reverts the optimistic change; a transient failure keeps it
// and queues a retry. Pass sendUpdates=true to email guests (attendee changes).
export function pushPatch(
  ev: CalEvent,
  body: object | null,
  revert: () => void,
  sendUpdates = false,
) {
  const t = googleTarget(ev.id);
  if (!t || !body) return;
  const key = ev.id!;
  if (patchInflight.has(key)) {
    patchPending.set(key, { body, revert, sendUpdates });
    return;
  }
  const run = (b: object, r: () => void, su: boolean): Promise<void> =>
    patchOnce(ev, t, b, su, r)
      .catch(() => enqueueWrite(() => patchOnce(ev, t, b, su, r)))
      .then(() => {
        const next = patchPending.get(key);
        if (next) {
          patchPending.delete(key);
          patchInflight.set(key, run(next.body, next.revert, next.sendUpdates));
        } else {
          patchInflight.delete(key);
        }
      });
  patchInflight.set(key, run(body, revert, sendUpdates));
}
