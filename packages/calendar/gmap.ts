// Mapping boundary: Google Calendar REST resources → the app's event/account
// shapes. Replaces the old gcalcli adapter (google.ts). Also orchestrates a full
// multi-account read (syncGoogle). Recurring events arrive pre-expanded
// (singleEvents=true), which is exactly what the per-day grid wants.
import {
  ACCOUNTS,
  allDayAsCalEvent,
  type AllDayEvent,
  type CalAccount,
  type CalEvent,
} from "./data";
import {
  COLOR_NAMES,
  DEFAULT_COLOR,
  PALETTE,
  eventColorName,
  nearestByHue,
  type Color,
} from "./palette";
import GLib from "gi://GLib";
import { accountEmails, accountPhotoUrl } from "./auth";
import { fetch } from "ags/fetch";
import {
  isTransient,
  listCalendars,
  meetLinkOf,
  searchEvents,
  syncEvents,
  type GEvent,
} from "./rest";
import { splitDescription } from "./gwrite";

// Palette colors (name → hex) excluding the neutral default, as hue candidates.
const PALETTE_CANDIDATES: [Color, string][] = COLOR_NAMES.filter(
  (c) => c !== DEFAULT_COLOR,
).map((c) => [c, PALETTE[c]]);

// Map a real Google color (calendar backgroundColor or event color hex) to the
// nearest palette color by HUE — Google's API returns the *pastel* form, so a
// straight RGB distance to the bold palette would pull most toward gray. Each
// pastel shares its bold counterpart's hue; desaturated colors → graphite.
const nearestColor = (hex?: string): Color =>
  hex ? nearestByHue(hex, PALETTE_CANDIDATES, DEFAULT_COLOR) : DEFAULT_COLOR;

// Stable, write-targetable id: account | calendar-id | event-id. Emails and
// Google ids contain no "|", so it splits cleanly in Phase C.
export const eventId = (account: string, calId: string, gid: string) =>
  `${account}|${calId}|${gid}`;

// Parse an id back into its parts (for REST writes).
export function parseEventId(id: string): {
  account: string;
  calId: string;
  gid: string;
} | null {
  const i = id.indexOf("|");
  const j = id.indexOf("|", i + 1);
  if (i < 0 || j < 0) return null;
  return {
    account: id.slice(0, i),
    calId: id.slice(i + 1, j),
    gid: id.slice(j + 1),
  };
}

// Google attendee responseStatus → our RSVP status (canonical read mapping;
// imported by store.ts for its on-demand attendee refresh).
export const RESP_IN: Record<string, CalEvent["status"]> = {
  accepted: "accepted",
  declined: "declined",
  tentative: "maybe",
  needsAction: "invited",
};

type Mapped =
  | { kind: "timed"; ev: CalEvent }
  | { kind: "allday"; ev: AllDayEvent };

// Google reminders → the app's model: useDefault defers to the calendar's
// defaults; otherwise the popup overrides (in minutes before). Email reminders
// are Google's job, so only popups are carried for desktop notifications.
function mapReminders(g: GEvent): {
  useDefaultReminders?: boolean;
  reminders?: number[];
} {
  const r = g.reminders;
  if (!r) return {};
  if (r.useDefault) return { useDefaultReminders: true };
  const mins = (r.overrides ?? [])
    .filter((o) => o.method === "popup" && typeof o.minutes === "number")
    .map((o) => o.minutes!);
  return { useDefaultReminders: false, reminders: mins };
}

function mapEvent(
  g: GEvent,
  account: string,
  calId: string,
  calName: string,
): Mapped | null {
  if (g.status === "cancelled" || !g.start) return null;
  const id = eventId(account, calId, g.id);
  const title = g.summary || "(No title)";
  const participants = (g.attendees ?? [])
    .map((a) => a.email)
    .filter(Boolean)
    .join(",");
  const self = g.attendees?.find((a) => a.self);
  const status = self?.responseStatus
    ? RESP_IN[self.responseStatus]
    : undefined;
  const attendeeStatus: NonNullable<CalEvent["attendeeStatus"]> = {};
  const optional: NonNullable<CalEvent["optional"]> = {};
  for (const a of g.attendees ?? []) {
    const st = a.responseStatus ? RESP_IN[a.responseStatus] : undefined;
    if (a.email && st) attendeeStatus[a.email] = st;
    if (a.email && a.optional) optional[a.email] = true;
  }
  const hasStatuses = Object.keys(attendeeStatus).length > 0;
  const hasOptional = Object.keys(optional).length > 0;
  // A per-event color (Google's event colorId) overrides the calendar's color.
  // No colorId → leave it unset so the event inherits its calendar's color.
  const evColor = g.colorId ? eventColorName(g.colorId) : undefined;
  // Links live in a trailing block of the description; pull them back out.
  const { description, links } = splitDescription(g.description || undefined);

  // All-day: start.date (no time component). Google's end.date is EXCLUSIVE, so
  // a multi-day span's inclusive last day is end.date − 1.
  if (g.start.date) {
    const [y, m, d] = g.start.date.split("-").map(Number);
    let endDate: [number, number, number] | undefined;
    if (g.end?.date) {
      const [ey, em, ed] = g.end.date.split("-").map(Number);
      const last = new Date(ey, em - 1, ed - 1);
      if (last.getTime() > new Date(y, m - 1, d).getTime())
        endDate = [last.getFullYear(), last.getMonth(), last.getDate()];
    }
    return {
      kind: "allday",
      ev: {
        id,
        title,
        color: evColor,
        calendar: calName,
        address: g.location || undefined,
        description,
        links,
        recurringEventId: g.recurringEventId,
        etag: g.etag,
        ...mapReminders(g),
        date: [y, m - 1, d],
        ...(endDate ? { endDate } : {}),
      },
    };
  }

  if (!g.start.dateTime) return null;
  // Timed: convert the RFC3339 instant to the user's local wall-clock hours.
  const s = new Date(g.start.dateTime);
  const start = s.getHours() + s.getMinutes() / 60;
  const startDay = new Date(s.getFullYear(), s.getMonth(), s.getDate());
  let end: number;
  let endDate: [number, number, number] | undefined;
  if (g.end?.dateTime) {
    const e = new Date(g.end.dateTime);
    let endHour = e.getHours() + e.getMinutes() / 60;
    // An end of exactly midnight belongs to the previous day (its 24:00), so a
    // 2pm–midnight event stays one day rather than spilling a 0-height segment.
    let endDay = new Date(e.getFullYear(), e.getMonth(), e.getDate());
    if (endHour === 0) {
      const prior = new Date(e.getTime() - 60000);
      endDay = new Date(prior.getFullYear(), prior.getMonth(), prior.getDate());
      endHour = 24;
    }
    end = endHour;
    if (endDay.getTime() > startDay.getTime())
      endDate = [endDay.getFullYear(), endDay.getMonth(), endDay.getDate()];
  } else {
    end = Math.min(start + 1, 24);
  }
  return {
    kind: "timed",
    ev: {
      id,
      title,
      start,
      end,
      color: evColor,
      calendar: calName,
      address: g.location || undefined,
      description,
      links,
      participants: participants || undefined,
      status,
      ...(hasStatuses ? { attendeeStatus } : {}),
      ...(hasOptional ? { optional } : {}),
      meetLink: meetLinkOf(g),
      timezone: g.start.timeZone || undefined,
      recurringEventId: g.recurringEventId,
      etag: g.etag,
      ...mapReminders(g),
      date: [s.getFullYear(), s.getMonth(), s.getDate()],
      ...(endDate ? { endDate } : {}),
    },
  };
}

// Account/calendar metadata for the sidebar, plus the (account,calId) pairs to
// sync events for (Google-deselected calendars are shown but not fetched).
export interface SyncMeta {
  accounts: CalAccount[];
  primary: string | null; // the primary calendar's name (default for new events)
  toSync: { account: string; calId: string; name: string }[];
  failed: string[]; // accounts whose calendar list couldn't be fetched this pass
}

// One calendar's change-set from a sync pass: mapped upserts, deleted event ids,
// the next token to persist, and whether the token expired (→ caller full-syncs).
export interface CalDelta {
  timed: CalEvent[];
  allDay: AllDayEvent[];
  deletedIds: string[];
  nextSyncToken?: string;
  expired: boolean;
}

const PHOTO_CACHE_DIR = `${GLib.get_user_cache_dir()}/calendar/photos`;

// Downloads and caches the profile photo for `email`. Returns the local path,
// or null if the URL is unavailable or the download fails.
async function cachePhoto(email: string): Promise<string | null> {
  const url = accountPhotoUrl(email);
  if (!url) return null;
  // Hash the email for the filename — it's used to build a filesystem path and
  // could contain path separators (or be the non-email "account" fallback).
  const name =
    GLib.compute_checksum_for_string(GLib.ChecksumType.SHA256, email, -1) ??
    encodeURIComponent(email);
  const dest = `${PHOTO_CACHE_DIR}/${name}`;
  try {
    const res = await fetch(url);
    if (res.status < 200 || res.status >= 300) return null;
    const buf = await res.arrayBuffer();
    GLib.mkdir_with_parents(PHOTO_CACHE_DIR, 0o700);
    GLib.file_set_contents(dest, new Uint8Array(buf as ArrayBuffer));
    return dest;
  } catch {
    return null;
  }
}

// True if any Google account is connected.
export const googleConfigured = (): boolean => accountEmails().length > 0;

// Full-text search every connected calendar (account × calendar) for `query`,
// across all time — so the search panel finds events outside the synced window.
// Returns timed + all-day events (all-day as a CalEvent), deduped by id.
// Per-calendar failures are swallowed so one bad calendar doesn't sink it.
export async function searchGoogle(query: string): Promise<CalEvent[]> {
  const q = query.trim();
  if (q.length < 2 || !googleConfigured()) return [];
  const targets: { account: string; calId: string; name: string }[] = [];
  for (const acct of ACCOUNTS)
    for (const c of acct.calendars)
      if (c.id)
        targets.push({ account: acct.account, calId: c.id, name: c.name });

  // Bounded concurrency: each keystroke-batch fans out one request per calendar,
  // so cap in-flight requests to avoid a rate-limit burst with many calendars.
  const LIMIT = 6;
  const lists: CalEvent[][] = [];
  let next = 0;
  const worker = async () => {
    while (next < targets.length) {
      const { account, calId, name } = targets[next++];
      const list = await searchEvents(account, calId, q)
        .then((gs) =>
          gs
            .map((g) => mapEvent(g, account, calId, name))
            .filter((m): m is Mapped => m != null)
            .map((m) => (m.kind === "timed" ? m.ev : allDayAsCalEvent(m.ev))),
        )
        .catch(() => [] as CalEvent[]);
      lists.push(list);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(LIMIT, targets.length) }, worker),
  );

  const seen = new Set<string>();
  const out: CalEvent[] = [];
  for (const ev of lists.flat())
    if (ev.id && !seen.has(ev.id)) {
      seen.add(ev.id);
      out.push(ev);
    }

  // Relevance by proximity to now: upcoming events first (soonest at the top),
  // then past events (most recent first) — so "the event in 5 min" leads, not
  // some match from years ago.
  const now = Date.now();
  const startMs = (e: CalEvent): number => {
    if (!e.date) return 0;
    const h = e.allDay || e.start == null ? 0 : e.start;
    return new Date(
      e.date[0],
      e.date[1],
      e.date[2],
      Math.floor(h),
      Math.round((h - Math.floor(h)) * 60),
    ).getTime();
  };
  out.sort((a, b) => {
    const sa = startMs(a);
    const sb = startMs(b);
    const fa = sa >= now;
    const fb = sb >= now;
    if (fa !== fb) return fa ? -1 : 1; // future before past
    return fa ? sa - sb : sb - sa; // upcoming asc, past desc
  });
  return out;
}

// List every connected account's calendars (for the sidebar) + the calendars to
// sync events for. One calendarList call per account — cheap, and gives colors,
// access role and the primary. Returns null only when no account is connected;
// per-account failures are logged and skipped.
export async function syncAccounts(): Promise<SyncMeta | null> {
  const emails = accountEmails();
  if (!emails.length) return null;

  const accounts: CalAccount[] = [];
  const toSync: SyncMeta["toSync"] = [];
  const failed: string[] = [];
  let primary: string | null = null;

  for (const email of emails) {
    // A rapid removal can delete an account mid-loop; skip rather than throw.
    if (!accountEmails().includes(email)) continue;
    let cals;
    try {
      cals = await listCalendars(email);
    } catch (err) {
      // Don't drop the account on a transient listCalendars failure (e.g. a 503)
      // — keep its last-known calendars in the sidebar and mark it failed so the
      // caller preserves its cached events instead of pruning them.
      if (!isTransient(err))
        console.error("calendar sync: listCalendars", email, err);
      const prev = ACCOUNTS.find((a) => a.account === email);
      if (prev) accounts.push(prev);
      failed.push(email);
      continue;
    }
    const calendars: CalAccount["calendars"] = [];
    for (const c of cals) {
      const color = nearestColor(c.backgroundColor);
      const writable = c.accessRole === "owner" || c.accessRole === "writer";
      // iCal/URL subscriptions are external feeds → flag as rss in the sidebar.
      const rss = c.id.includes("import.calendar.google.com");
      const defaultReminders = (c.defaultReminders ?? [])
        .filter((r) => r.method === "popup" && typeof r.minutes === "number")
        .map((r) => r.minutes!);
      calendars.push({
        name: c.summary,
        color,
        writable,
        rss,
        id: c.id,
        defaultReminders,
      });
      if (c.primary && primary === null) primary = c.summary;
      if (c.selected !== false)
        toSync.push({ account: email, calId: c.id, name: c.summary });
    }
    const photo = await cachePhoto(email);
    accounts.push({ account: email, calendars, ...(photo ? { photo } : {}) });
  }
  return { accounts, primary, toSync, failed };
}

// Sync one calendar: incremental when given a token (changes since), else a full
// windowed fetch. Maps results to events; cancellations become deletedIds.
export async function fetchCalendarSync(
  account: string,
  calId: string,
  calName: string,
  opts: { syncToken?: string; timeMin?: Date; timeMax?: Date },
): Promise<CalDelta> {
  const page = await syncEvents(account, calId, opts);
  if (page.expired)
    return { timed: [], allDay: [], deletedIds: [], expired: true };
  const timed: CalEvent[] = [];
  const allDay: AllDayEvent[] = [];
  const deletedIds: string[] = [];
  for (const g of page.events) {
    if (g.status === "cancelled") {
      deletedIds.push(eventId(account, calId, g.id));
      continue;
    }
    const m = mapEvent(g, account, calId, calName);
    if (!m) continue;
    if (m.kind === "timed") timed.push(m.ev);
    else allDay.push(m.ev);
  }
  return {
    timed,
    allDay,
    deletedIds,
    nextSyncToken: page.nextSyncToken,
    expired: false,
  };
}
