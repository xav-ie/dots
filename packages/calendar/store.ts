// Public mutation API: every user edit applies optimistically to the in-memory
// event + cache (bumping `rev` to re-render), then pushes the change to Google.
// New events are created on Google when their editor closes (if edited). The
// shared index/cache primitives live in eventIndex, the optimistic PATCH path in
// writeQueue, and the reconcile-from-Google engine in sync.
import {
  ACCOUNTS,
  ALL_DAY,
  EVENTS,
  resetCalColor,
  type AllDayEvent,
  type CalEvent,
} from "./data";
import * as db from "./db";
import {
  byId,
  calTarget,
  decache,
  googleTarget,
  isAllDay,
  reassignId,
  recache,
  setRev,
  type AnyEvent,
} from "./eventIndex";
import { syncNow } from "./sync";
import { enqueueWrite, pushPatch } from "./writeQueue";
import { RESP_IN, parseEventId } from "./gmap";
import {
  combineDescription,
  eventBody,
  fieldBody,
  recurrenceUntil,
  remindersBody,
  rewriteCount,
  startEndBody,
} from "./gwrite";
import { notify } from "./notify";
import { PALETTE, foregroundFor, type Color } from "./palette";
import {
  getEvent,
  insertEvent,
  isTransient,
  listInstances,
  meetLinkOf,
  moveEvent,
  patchEvent,
  addMeet as restAddMeet,
  deleteEvent as restDeleteEvent,
  setCalendarColor as restSetCalendarColor,
  type GEvent,
} from "./rest";
import {
  askRecurScope,
  defaultCal,
  selected,
  setAccounts,
  type RecurScope,
} from "./state";

// Re-exported so existing consumers keep importing the grid signal and the sync
// trigger from "./store" even though they now live in dedicated modules.
export { rev } from "./eventIndex";
export { syncNow } from "./sync";

let createCounter = 0;

// The currently-open new event (a draft) + a snapshot of its content when its
// editor opened. On close: unchanged → discarded; changed → created on Google.
let draft: { id: string; snap: string } | null = null;

// Local draft ids currently being created on Google. Guards the close-handler
// from firing a second insert while addMeet's create is still in flight (which
// would duplicate the event). Keyed by the original "local|…" id.
const creating = new Set<string>();

// --- recurring series --------------------------------------------------------

// The occurrence's local start instant (for computing a precise UNTIL boundary).
function occurrenceStart(ev: CalEvent): Date {
  const [y, m, d] = ev.date!;
  if (isAllDay(ev)) return new Date(y, m, d);
  const h = ev.start ?? 0;
  return new Date(y, m, d, Math.floor(h), Math.round((h - Math.floor(h)) * 60));
}

// The series base's Google target for a recurring occurrence, or null when the
// event isn't a synced recurring instance (so it takes the normal single path).
function recurBase(
  e: AnyEvent,
): { account: string; calId: string; gid: string } | null {
  const t = googleTarget(e.id);
  const rid = (e as CalEvent).recurringEventId;
  return t && rid ? { account: t.account, calId: t.calId, gid: rid } : null;
}

// Build an events.insert/patch body from a fetched series base (content fields
// + recurrence), with explicit start/end. Used to recreate a series when it's
// split ("this and following") or moved wholesale to another calendar.
function seriesBodyFrom(
  g: GEvent,
  startEnd: { start: object; end: object },
): Record<string, unknown> {
  const b: Record<string, unknown> = {
    summary: g.summary ?? "New event",
    ...startEnd,
  };
  if (g.recurrence) b.recurrence = g.recurrence;
  if (g.description) b.description = g.description;
  if (g.location) b.location = g.location;
  if (g.colorId) b.colorId = g.colorId;
  if (g.transparency) b.transparency = g.transparency;
  if (g.visibility) b.visibility = g.visibility;
  if (g.attendees)
    b.attendees = g.attendees
      .map((a) => a.email)
      .filter(Boolean)
      .map((email) => ({ email }));
  return b;
}

// "This and following": end the old series the day before `ev`, then start a new
// series at `ev` carrying the base content plus `edits`. Re-syncs from Google
// (the truth) rather than splicing the many affected occurrences locally.
async function splitSeries(
  ev: CalEvent,
  base: { account: string; calId: string; gid: string },
  edits: object,
) {
  const g = await getEvent(base.account, base.calId, base.gid);
  await patchEvent(base.account, base.calId, base.gid, {
    recurrence: recurrenceUntil(
      g.recurrence,
      occurrenceStart(ev),
      isAllDay(ev),
    ),
  });
  const body: Record<string, unknown> = {
    ...seriesBodyFrom(g, startEndBody(ev, isAllDay(ev))),
    ...edits,
  };
  // Unless the edit itself sets a new rule, the new series inherits the old one
  // with any COUNT reduced to the occurrences that survive the split.
  if (!("recurrence" in edits)) {
    const rec = await splitRecurrence(base, g, ev);
    if (rec) body.recurrence = rec;
    else delete body.recurrence;
  }
  await insertEvent(base.account, base.calId, body);
  await syncNow();
}

// Recurrence for the post-split (new) series: a COUNT-bounded rule must keep only
// the occurrences from the split point on, else the new series restarts the full
// count. The remaining count comes from Google's own (DST-correct) expansion.
async function splitRecurrence(
  base: { account: string; calId: string; gid: string },
  g: GEvent,
  ev: CalEvent,
): Promise<string[] | undefined> {
  const rec = g.recurrence;
  if (!rec || !rec.some((l) => /COUNT=\d+/.test(l))) return rec;
  const boundary = new Date(ev.date![0], ev.date![1], ev.date![2]).getTime();
  const insts = await listInstances(base.account, base.calId, base.gid);
  const remaining = insts.filter((i) => {
    const s = i.start?.dateTime ?? i.start?.date;
    return s ? new Date(s).getTime() >= boundary : false;
  }).length;
  return rewriteCount(rec, remaining);
}

// Move a recurring event to another calendar at the chosen scope. "all" moves
// the whole series (events.move same-account, copy+delete across accounts);
// "this" drops this occurrence and drops a one-off copy on the destination;
// "following" truncates the source series and starts a new one on the
// destination. Always reconciles via a sync afterwards.
async function moveRecurring(
  ev: CalEvent,
  base: { account: string; calId: string; gid: string },
  dest: { account: string; calId: string },
  scope: RecurScope,
) {
  const g = await getEvent(base.account, base.calId, base.gid);
  if (scope === "all") {
    if (dest.account === base.account)
      await moveEvent(base.account, base.calId, base.gid, dest.calId);
    else {
      await insertEvent(
        dest.account,
        dest.calId,
        seriesBodyFrom(g, { start: g.start ?? {}, end: g.end ?? {} }),
      );
      await restDeleteEvent(base.account, base.calId, base.gid);
    }
  } else if (scope === "this") {
    const inst = parseEventId(ev.id!);
    await insertEvent(
      dest.account,
      dest.calId,
      eventBody({ ...ev, recur: undefined }, isAllDay(ev)),
    );
    if (inst) await restDeleteEvent(inst.account, inst.calId, inst.gid);
  } else {
    await patchEvent(base.account, base.calId, base.gid, {
      recurrence: recurrenceUntil(
        g.recurrence,
        occurrenceStart(ev),
        isAllDay(ev),
      ),
    });
    const body = seriesBodyFrom(g, startEndBody(ev, isAllDay(ev)));
    const rec = await splitRecurrence(base, g, ev);
    if (rec) body.recurrence = rec;
    else delete body.recurrence;
    await insertEvent(dest.account, dest.calId, body);
  }
  await syncNow();
}

// Push a start/end (or all-day) change already applied to `e`. For a recurring
// instance, ask whether it affects just this occurrence (records an exception)
// or this and following (splits the series here). A series-wide "all" time shift
// isn't offered — pick the first occurrence + "following" for that. A
// non-recurring event writes straight through.
function pushTiming(e: CalEvent, body: object, revert: () => void) {
  const base = recurBase(e);
  if (!base) {
    pushPatch(e, body, revert);
    return;
  }
  void askRecurScope({
    verb: "edit",
    title: e.title,
    allow: { all: false },
  }).then((scope) => {
    if (!scope) return revert();
    if (scope === "this") {
      pushPatch(e, body, revert);
    } else {
      // splitSeries rebuilds the new series from `e`'s (already-applied) start/
      // end + all-day state, so no edits object is needed.
      splitSeries(e, base, {}).catch((err) => {
        notify(`Couldn't update following events — ${err}`);
        revert();
        void syncNow();
      });
    }
  });
}

// --- attendees / RSVP --------------------------------------------------------

// App RSVP status → Google attendee responseStatus.
const RESP: Record<string, string> = {
  accepted: "accepted",
  declined: "declined",
  maybe: "tentative",
  invited: "needsAction",
};

// Write the signed-in user's RSVP by patching their attendee entry. We fetch the
// event first so the other guests' responses and the organizer flag survive the
// array-replacing PATCH, and notify the organizer (sendUpdates=all). No-op if
// you're not on the guest list.
async function rsvp(
  t: { account: string; calId: string; gid: string },
  status: string,
  revert: () => void,
) {
  const resp = RESP[status];
  if (!resp) return;
  try {
    const g = await getEvent(t.account, t.calId, t.gid);
    const acct = t.account.toLowerCase();
    const self =
      g.attendees?.find((a) => a.self) ??
      g.attendees?.find((a) => a.email?.toLowerCase() === acct);
    if (!self) return; // not an attendee — nothing to respond to
    self.responseStatus = resp;
    await patchEvent(
      t.account,
      t.calId,
      t.gid,
      { attendees: g.attendees },
      true,
    );
  } catch (err) {
    // Offline / server blip → keep the change and replay on reconnect.
    if (isTransient(err)) enqueueWrite(() => rsvp(t, status, revert));
    else {
      notify(`Couldn't update RSVP — ${err}`);
      revert();
    }
  }
}

// Attach a Google Meet conference to an event and adopt the returned join link.
// A still-local draft (new event, not yet created on close) is created on Google
// first so it has an id to attach the conference to.
export async function addMeet(ev: CalEvent) {
  let t = googleTarget(ev.id);
  if (!t) {
    const oldId = ev.id;
    await createOnGoogle(ev);
    // createOnGoogle re-keys ev.id; clear the draft so the editor's close handler
    // doesn't try to create it a second time.
    if (draft && draft.id === oldId) draft = null;
    t = googleTarget(ev.id);
    if (!t) return; // creation failed (createOnGoogle already notified)
  }
  try {
    const g = await restAddMeet(t.account, t.calId, t.gid);
    ev.etag = g.etag;
    const link = meetLinkOf(g);
    if (link) {
      ev.meetLink = link;
      recache(ev);
      setRev((n) => n + 1);
    }
  } catch (err) {
    notify(`Couldn't add Google Meet — ${err}`);
  }
}

// The real event object for an id (the grid may render a per-day clamped copy of
// a multi-day event; the editor must open the real one).
export const liveEvent = (id: string | undefined): CalEvent | undefined =>
  id ? (byId.get(id) as CalEvent | undefined) : undefined;

// The live RSVP status for one attendee (read from the current event in byId, so
// it reflects the latest sync even if the editor holds an older reference). Email
// match is case-insensitive — the rows are keyed off `participants` (as-typed)
// while Google normalizes attendee emails to lowercase.
export function attendeeStatusOf(
  id: string | undefined,
  email: string,
): CalEvent["status"] {
  if (!id) return undefined;
  const m = (byId.get(id) as CalEvent | undefined)?.attendeeStatus;
  if (!m) return undefined;
  if (m[email]) return m[email];
  const lower = email.toLowerCase();
  for (const k in m) if (k.toLowerCase() === lower) return m[k];
  return undefined;
}

// Pull the event's current attendee responses (their RSVPs change on Google when
// guests accept/decline) and update the in-memory event, so opening an event
// shows fresh checkmarks without waiting for the next background sync. RESP_IN
// (Google→app) is the canonical read map from gmap.
export async function refreshAttendees(ev: CalEvent) {
  const t = googleTarget(ev.id);
  if (!t) return; // local draft — nothing on Google yet
  try {
    const g = await getEvent(t.account, t.calId, t.gid);
    const status: NonNullable<CalEvent["attendeeStatus"]> = {};
    const optional: NonNullable<CalEvent["optional"]> = {};
    for (const a of g.attendees ?? []) {
      if (!a.email) continue;
      const st = a.responseStatus ? RESP_IN[a.responseStatus] : undefined;
      if (st) status[a.email] = st;
      if (a.optional) optional[a.email] = true;
    }
    // Update the LIVE event in byId (a background sync may have replaced the
    // object the editor still references), so attendeeStatusOf reads the change.
    const live = (byId.get(ev.id!) as CalEvent | undefined) ?? ev;
    live.attendeeStatus = Object.keys(status).length ? status : undefined;
    live.optional = Object.keys(optional).length ? optional : undefined;
    if (g.etag) live.etag = g.etag;
    recache(live);
    setRev((n) => n + 1);
  } catch {
    // offline / transient — the background sync will catch it up
  }
}

// Mark one attendee optional/required on Google (fetch-merge so other guests'
// fields survive). Updates the in-memory event's `optional` map optimistically.
export async function setAttendeeOptional(
  ev: CalEvent,
  email: string,
  optional: boolean,
) {
  const map = { ...(ev.optional ?? {}) };
  if (optional) map[email] = true;
  else delete map[email];
  ev.optional = map;
  recache(ev);
  const t = googleTarget(ev.id);
  if (!t) return; // local draft — persisted with the event on close
  try {
    const g = await getEvent(t.account, t.calId, t.gid);
    const a = g.attendees?.find((x) => x.email === email);
    if (!a) return;
    a.optional = optional;
    const etag = await patchEvent(t.account, t.calId, t.gid, {
      attendees: g.attendees,
    });
    if (etag) {
      ev.etag = etag;
      recache(ev);
    }
  } catch (err) {
    // Offline / server blip → keep the change and replay on reconnect.
    if (isTransient(err))
      enqueueWrite(() => setAttendeeOptional(ev, email, optional));
    else notify(`Couldn't update guest — ${err}`);
  }
}

// Reconcile an event's guest list to `emails`, preserving the existing
// attendees' responseStatus and the organizer/self entries — a bare-email PATCH
// replaces the whole array and would reset everyone's RSVP to needsAction (and
// re-invite them). Notifies guests of the change (sendUpdates=all). Reverts on
// failure.
async function writeAttendees(
  t: { account: string; calId: string; gid: string },
  emails: string[],
  revert: () => void,
) {
  try {
    const g = await getEvent(t.account, t.calId, t.gid);
    // Google lowercases attendee emails; compare case-insensitively so the
    // self/organizer entry is preserved and existing guests aren't re-added.
    const acct = t.account.toLowerCase();
    const want = new Set(emails.map((e) => e.toLowerCase()));
    const kept = (g.attendees ?? []).filter(
      (a) =>
        a.email &&
        (want.has(a.email.toLowerCase()) ||
          a.self ||
          a.email.toLowerCase() === acct),
    );
    const have = new Set(kept.map((a) => a.email?.toLowerCase()));
    const added = emails
      .filter((e) => !have.has(e.toLowerCase()))
      .map((email) => ({ email }));
    await patchEvent(
      t.account,
      t.calId,
      t.gid,
      { attendees: [...kept, ...added] },
      true,
    );
  } catch (err) {
    // Offline / server blip → keep the change and replay on reconnect.
    if (isTransient(err)) enqueueWrite(() => writeAttendees(t, emails, revert));
    else {
      notify(`Couldn't update guests — ${err}`);
      revert();
    }
  }
}

// --- create / move / delete --------------------------------------------------

// Create a (so-far local) event on Google, then adopt its real id. Re-entrant
// calls for the same draft (e.g. addMeet creating + the close handler firing)
// are dropped via `creating` so the event isn't inserted twice.
async function createOnGoogle(ev: CalEvent) {
  const localId = ev.id;
  if (!localId || creating.has(localId)) return;
  const target = calTarget(ev.calendar ?? defaultCal.get());
  if (!target) return; // dummy / no writable calendar
  creating.add(localId);
  try {
    const created = await insertEvent(
      target.account,
      target.calId,
      eventBody(ev, isAllDay(ev)),
      !!ev.participants, // email guests when creating an event that has them
    );
    ev.etag = created.etag;
    reassignId(ev, `${target.account}|${target.calId}|${created.id}`);
    setRev((n) => n + 1);
  } catch (err) {
    notify(`Couldn't create event — ${err}`);
  } finally {
    creating.delete(localId);
  }
}

// Move an event to another calendar: apply locally (adopting the new calendar's
// color unless the event has its own color override), then move it on Google and
// re-key it. Same-account uses events.move; across accounts Google can't move, so
// we copy into the destination and delete the source (new id/organizer). Reverts
// the local change on failure so the cache never disagrees with Google. A local
// (not-yet-synced) event is just created under the new calendar when it closes.
function moveCalendar(ev: CalEvent, newCalName: string, refresh: boolean) {
  const old = ev.calendar;
  // An event with no color override inherits the destination calendar's color
  // automatically (resolved at render via eventColor) — nothing to reassign.
  ev.calendar = newCalName;
  recache(ev);
  if (refresh) setRev((n) => n + 1);

  const t = googleTarget(ev.id);
  if (!t) return; // local event — created under newCalName on close
  const dest = calTarget(newCalName, t.account);
  const revert = (why: string) => {
    notify(`Couldn't move event — ${why}`);
    ev.calendar = old;
    recache(ev);
    setRev((n) => n + 1);
  };
  if (!dest) return revert("destination calendar has no id");

  // Recurring: ask which occurrences move, then reconcile from Google.
  const base = recurBase(ev);
  if (base) {
    void askRecurScope({
      verb: "move",
      title: ev.title,
      dest: newCalName,
    }).then((scope) => {
      if (!scope) return revert("cancelled");
      moveRecurring(ev, base, dest, scope).catch((err) => {
        revert(String(err));
        void syncNow();
      });
    });
    return;
  }

  const adopt = (newId: string, etag?: string) => {
    if (etag) ev.etag = etag;
    reassignId(ev, newId);
    setRev((n) => n + 1);
  };
  if (dest.account === t.account) {
    void moveEvent(t.account, t.calId, t.gid, dest.calId)
      .then((g) => adopt(`${dest.account}|${dest.calId}|${t.gid}`, g.etag))
      .catch((err) => revert(String(err)));
  } else {
    void (async () => {
      try {
        const created = await insertEvent(
          dest.account,
          dest.calId,
          eventBody(ev, isAllDay(ev)),
        );
        await restDeleteEvent(t.account, t.calId, t.gid);
        adopt(`${dest.account}|${dest.calId}|${created.id}`, created.etag);
      } catch (err) {
        revert(String(err));
      }
    })();
  }
}

// Create a new (dated) event under `calendar` and open it.
export function createEvent(opts: {
  title: string;
  start: number;
  end: number;
  date: Date;
  calendar: string;
}): CalEvent {
  const id = `local|local|c${Date.now()}-${createCounter++}`;
  const ymd: [number, number, number] = [
    opts.date.getFullYear(),
    opts.date.getMonth(),
    opts.date.getDate(),
  ];
  const ev: CalEvent = {
    id,
    title: opts.title,
    start: opts.start,
    end: opts.end,
    calendar: opts.calendar, // color unset → inherits the calendar's color
    date: ymd,
  };
  EVENTS.push(ev);
  byId.set(id, ev);
  recache(ev);
  setRev((n) => n + 1);
  return ev;
}

// Remove an event from the grid + cache locally (shared by every delete path).
function removeLocal(id: string) {
  const e = byId.get(id);
  if (e) {
    const ei = EVENTS.indexOf(e as CalEvent);
    if (ei >= 0) EVENTS.splice(ei, 1);
    const ai = ALL_DAY.indexOf(e as AllDayEvent);
    if (ai >= 0) ALL_DAY.splice(ai, 1);
    byId.delete(id);
  }
  if (draft?.id === id) draft = null; // don't create-on-close a deleted draft
  decache(id);
  setRev((n) => n + 1);
}

export function deleteEvent(id: string | undefined) {
  if (!id) return;
  const e = byId.get(id);
  const base = e && recurBase(e);
  if (e && base) {
    const ev = e as CalEvent;
    const notifyGuests = !!ev.participants; // email guests on cancellation
    void askRecurScope({ verb: "delete", title: ev.title }).then((scope) => {
      if (!scope) return;
      removeLocal(id); // drop the clicked occurrence now; sync reconciles the rest
      const inst = parseEventId(id)!;
      const op =
        scope === "all"
          ? restDeleteEvent(base.account, base.calId, base.gid, notifyGuests) // whole series
          : scope === "this"
            ? restDeleteEvent(inst.account, inst.calId, inst.gid, notifyGuests) // one occurrence
            : getEvent(base.account, base.calId, base.gid).then((g) =>
                patchEvent(
                  base.account,
                  base.calId,
                  base.gid,
                  {
                    recurrence: recurrenceUntil(
                      g.recurrence,
                      occurrenceStart(ev),
                      isAllDay(ev),
                    ),
                  },
                  notifyGuests,
                ),
              );
      op.then(() => (scope === "this" ? undefined : syncNow())).catch((err) => {
        notify(`Couldn't delete event — ${err}`);
        void syncNow();
      });
    });
    return;
  }
  const target = googleTarget(id);
  const notifyGuests = !!(e as CalEvent | undefined)?.participants;
  removeLocal(id);
  if (target)
    void restDeleteEvent(
      target.account,
      target.calId,
      target.gid,
      notifyGuests,
    ).catch((err) => notify(`Couldn't delete event — ${err}`));
}

// --- field mutations ---------------------------------------------------------

export function setEventDate(id: string | undefined, date: Date) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const oldDate = e.date;
  e.date = [date.getFullYear(), date.getMonth(), date.getDate()];
  recache(e);
  setRev((n) => n + 1);
  pushPatch(e, startEndBody(e, isAllDay(e)), () => {
    e.date = oldDate;
    recache(e);
    setRev((n) => n + 1);
  });
}

// Set the event's end day (a multi-day span). On/before the start day → single
// day (endDate cleared). Writes the new start/end to Google.
export function setEndDate(id: string | undefined, date: Date) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const old = e.endDate;
  const d: [number, number, number] = [
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
  ];
  const start = e.date ?? d;
  const dayNum = (a: [number, number, number]) =>
    new Date(a[0], a[1], a[2]).getTime();
  e.endDate = dayNum(d) > dayNum(start) ? d : undefined;
  recache(e);
  setRev((n) => n + 1);
  pushPatch(e, startEndBody(e, isAllDay(e)), () => {
    e.endDate = old;
    recache(e);
    setRev((n) => n + 1);
  });
}

// Set an event's popup reminders (minutes before). Reminders are per-user and
// series-wide, so a recurring event applies them to the base (no scope prompt);
// otherwise the event is PATCHed directly.
export function setReminders(id: string | undefined, minutes: number[]) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const prev = {
    reminders: e.reminders,
    useDefaultReminders: e.useDefaultReminders,
  };
  e.reminders = minutes;
  e.useDefaultReminders = false;
  recache(e);
  setRev((n) => n + 1);
  const revert = () => {
    e.reminders = prev.reminders;
    e.useDefaultReminders = prev.useDefaultReminders;
    recache(e);
    setRev((n) => n + 1);
  };
  const base = recurBase(e);
  if (base) {
    patchEvent(base.account, base.calId, base.gid, remindersBody(e))
      .then(() => syncNow())
      .catch((err) => {
        notify(`Couldn't update reminders — ${err}`);
        revert();
        void syncNow();
      });
    return;
  }
  pushPatch(e, remindersBody(e), revert);
}

// Toggle whether an event lives in the all-day row.
export function setAllDay(id: string | undefined, on: boolean) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const prev = {
    allDay: e.allDay,
    start: e.start,
    end: e.end,
    endDate: e.endDate,
    inAllDay: ALL_DAY.includes(e as unknown as AllDayEvent),
  };
  e.allDay = on;
  // A toggled event is single-day — drop any multi-day span so it doesn't render
  // across days (and so the timed start/end are unambiguous).
  e.endDate = undefined;
  if (!on && (e.start == null || e.start === e.end)) {
    e.start = 9;
    e.end = 10;
  }
  if (!on && !EVENTS.includes(e)) {
    EVENTS.push(e);
    const ai = ALL_DAY.indexOf(e as unknown as AllDayEvent);
    if (ai >= 0) ALL_DAY.splice(ai, 1);
  }
  recache(e);
  setRev((n) => n + 1);
  // clearOther=true: toggling type must null the opposite (date↔dateTime) field.
  pushTiming(e, startEndBody(e, on, true), () => {
    e.allDay = prev.allDay;
    e.start = prev.start;
    e.end = prev.end;
    e.endDate = prev.endDate;
    if (prev.inAllDay && !ALL_DAY.includes(e as unknown as AllDayEvent)) {
      ALL_DAY.push(e as unknown as AllDayEvent);
      const ei = EVENTS.indexOf(e);
      if (ei >= 0) EVENTS.splice(ei, 1);
    }
    recache(e);
    setRev((n) => n + 1);
  });
}

// Persist + apply one field. `refresh` re-renders the grid for visible changes.
export function updateEvent(
  id: string | undefined,
  field: keyof CalEvent,
  value: string,
  refresh = false,
) {
  if (!id) return;
  const e = byId.get(id);
  if (!e) return;
  if (field === "calendar") {
    moveCalendar(e as CalEvent, value, refresh);
    return;
  }
  const ce = e as CalEvent;
  const oldVal = (e as unknown as Record<string, unknown>)[field];
  (e as unknown as Record<string, unknown>)[field] = value;
  recache(e);
  if (refresh) setRev((n) => n + 1);
  const revert = () => {
    (e as unknown as Record<string, unknown>)[field] = oldVal;
    recache(e);
    setRev((n) => n + 1);
  };

  // Time zone is series-wide: for a recurring event change the base's start/end
  // zone (keeping its own dates); otherwise PATCH this event's times.
  if (field === "timezone") {
    const tzBase = recurBase(e);
    if (tzBase)
      void getEvent(tzBase.account, tzBase.calId, tzBase.gid)
        .then((g) =>
          patchEvent(tzBase.account, tzBase.calId, tzBase.gid, {
            start: { ...g.start, timeZone: value },
            end: { ...g.end, timeZone: value },
          }),
        )
        .then(() => syncNow())
        .catch((err) => {
          notify(`Couldn't change time zone — ${err}`);
          revert();
          void syncNow(); // the base PATCH may have partly landed — reconcile
        });
    else pushPatch(ce, startEndBody(ce, isAllDay(e)), revert);
    return;
  }

  // RSVP: patch the signed-in user's attendee responseStatus. "this" vs "all" for
  // a recurring event; there's no "this and following" RSVP.
  if (field === "status") {
    const inst = googleTarget(ce.id);
    if (!inst) return; // local/dummy
    const rb = recurBase(e);
    if (!rb) {
      void rsvp(inst, value, revert);
      return;
    }
    void askRecurScope({
      verb: "edit",
      title: ce.title,
      allow: { following: false },
    }).then((scope) => {
      if (!scope) return revert();
      void rsvp(scope === "all" ? rb : inst, value, revert);
    });
    return;
  }

  // Guest list: merge into the live attendees (preserving RSVPs) and notify.
  if (field === "participants") {
    const t = googleTarget(ce.id);
    if (!t) return; // local/dummy — created with attendees on close
    const emails = value ? value.split(",").filter(Boolean) : [];
    const rb = recurBase(e);
    if (!rb) {
      void writeAttendees(t, emails, revert);
      return;
    }
    // Recurring: change the whole series' guest list or just this occurrence's
    // (no "this and following" form for attendees).
    void askRecurScope({
      verb: "edit",
      title: ce.title,
      allow: { following: false },
    }).then((scope) => {
      if (!scope) return revert();
      void writeAttendees(scope === "all" ? rb : t, emails, revert);
    });
    return;
  }

  // Body for editing this single field (date-independent for all of these, so
  // it's safe to apply to the series base as well as one instance). Links are
  // folded into the description.
  const body =
    field === "description" || field === "links"
      ? { description: combineDescription(ce.description, ce.links) }
      : fieldBody(field, value);

  const base = recurBase(e);
  if (!base) {
    pushPatch(ce, body, revert);
    return;
  }
  // Description / links are series-wide content — apply straight to the base so
  // adding several links doesn't raise a scope dialog per edit.
  if (field === "description" || field === "links") {
    if (!body) return;
    patchEvent(base.account, base.calId, base.gid, body)
      .then(() => syncNow())
      .catch((err) => {
        notify(`Couldn't save change — ${err}`);
        revert();
        void syncNow();
      });
    return;
  }
  // Recurring: pick scope. Changing the repeat rule has no per-occurrence form.
  void askRecurScope({
    verb: "edit",
    title: ce.title,
    allow: field === "recur" ? { this: false } : {},
  }).then((scope) => {
    if (!scope) return revert();
    if (scope === "this") {
      pushPatch(ce, body, revert); // PATCH the instance → Google records an exception
    } else if (scope === "all") {
      if (!body) return;
      patchEvent(base.account, base.calId, base.gid, body)
        .then(() => syncNow())
        .catch((err) => {
          notify(`Couldn't save change — ${err}`);
          revert();
        });
    } else {
      if (!body) return;
      splitSeries(ce, base, body).catch((err) => {
        notify(`Couldn't update following events — ${err}`);
        revert();
        void syncNow();
      });
    }
  });
}

// Reschedule an event (drag): new start/end.
export function setEventTime(
  id: string | undefined,
  start: number,
  end: number,
) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const oldS = e.start;
  const oldE = e.end;
  e.start = start;
  e.end = end;
  recache(e);
  setRev((n) => n + 1);
  pushTiming(e, startEndBody(e, isAllDay(e)), () => {
    e.start = oldS;
    e.end = oldE;
    recache(e);
    setRev((n) => n + 1);
  });
}

// Merge draft invitees into an event's participants and push to Google with
// sendUpdates=all so the new attendees actually receive invite emails. Preserves
// existing guests' RSVPs (writeAttendees fetch-merges rather than overwriting).
export function commitInvites(
  ev: CalEvent,
  emails: string[],
  onFail?: () => void,
) {
  const merged = ev.participants
    ? ev.participants.split(",").filter(Boolean)
    : [];
  for (const e of emails) if (!merged.includes(e)) merged.push(e);
  const old = ev.participants;
  ev.participants = merged.join(",");
  recache(ev);
  const t = googleTarget(ev.id);
  if (!t) return; // local draft — created with attendees on close
  void writeAttendees(t, merged, () => {
    ev.participants = old;
    recache(ev);
    setRev((n) => n + 1);
    onFail?.(); // let the editor roll back its optimistic saved-list update
  });
}

// Recolor a calendar: optimistically update the calendar entry, its events, the
// color map and the cache, then write the color back to Google (a per-user
// calendarList setting). `calId`/`account` come from the sync; the dummy seeds
// have no id, so those stay local-only.
export function setCalendarColor(
  account: string,
  calId: string | undefined,
  calName: string,
  color: Color,
) {
  for (const a of ACCOUNTS)
    for (const c of a.calendars) if (c.name === calName) c.color = color;
  resetCalColor();
  // Events don't store the calendar's color — they resolve it at render via
  // eventColor — so a recolor is just the calendar entry + a re-render. No event
  // rows are rewritten (the old per-event cache write froze the app on big
  // calendars); events with their own color override are correctly untouched.
  // New array refs so the sidebar <For> re-renders the swatches.
  setAccounts(ACCOUNTS.map((a) => ({ ...a, calendars: [...a.calendars] })));
  db.setCachedAccounts(ACCOUNTS);
  setRev((n) => n + 1);

  if (!calId) return; // dummy seed — local only
  const hex = PALETTE[color];
  void restSetCalendarColor(account, calId, hex, foregroundFor(hex)).catch(
    (err) => notify(`Couldn't set calendar color — ${err}`),
  );
}

// Move a dated event to a new day + time (drag across days).
export function setEventMove(
  id: string | undefined,
  date: Date,
  start: number,
  end: number,
) {
  if (!id) return;
  const e = byId.get(id) as CalEvent | undefined;
  if (!e) return;
  const oldDate = e.date;
  const oldS = e.start;
  const oldE = e.end;
  e.date = [date.getFullYear(), date.getMonth(), date.getDate()];
  e.start = start;
  e.end = end;
  recache(e);
  setRev((n) => n + 1);
  pushPatch(e, startEndBody(e, isAllDay(e)), () => {
    e.date = oldDate;
    e.start = oldS;
    e.end = oldE;
    recache(e);
    setRev((n) => n + 1);
  });
}

// --- draft lifecycle ---------------------------------------------------------

// Discard an untouched draft: when a freshly-created event's editor opens we
// snapshot its content; if the selection moves away (panel closed, another event
// picked) with the content byte-for-byte unchanged, delete it. Comparing content
// — not tracking edits — correctly ignores no-op title blur-commits.
function snapshot(e: AnyEvent): string {
  const c = e as CalEvent;
  return JSON.stringify([
    e.title,
    c.start,
    c.end,
    e.date,
    e.calendar,
    e.color,
    c.allDay,
    e.address,
    e.description,
    c.participants,
    c.status,
    c.freeBusy,
    c.visibility,
    c.timezone,
    c.links,
    c.recur,
  ]);
}

selected.subscribe(() => {
  const sel = selected.get();
  if (draft && sel?.ev.id !== draft.id) {
    const e = byId.get(draft.id);
    if (e) {
      // Untouched → discard; edited → create it on Google (unless a create for
      // this draft is already in flight, e.g. triggered by addMeet).
      if (snapshot(e) === draft.snap) deleteEvent(draft.id);
      else if (!creating.has(draft.id)) void createOnGoogle(e as CalEvent);
    }
    draft = null;
  }
  if (sel?.isNew && sel.ev.id)
    draft = { id: sel.ev.id, snap: snapshot(sel.ev) };
});
