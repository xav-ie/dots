// Google Calendar v3 REST client. Authenticated via auth.ts. Uses libsoup and
// retries once on 401 by forcing a token refresh.
import GLib from "gi://GLib";
import Soup from "gi://Soup?version=3.0";
import { URLSearchParams } from "ags/fetch";
import { accessTokenFor } from "./auth";

const BASE = "https://www.googleapis.com/calendar/v3";

// Classify a request failure (errors thrown by authedSend embed "→ NNN"): a
// transport failure (offline) has no status; a 5xx/429 is retryable; any other
// 4xx is a permanent rejection.
export function isTransient(err: unknown): boolean {
  const m = String(err).match(/→ (\d{3})\b/);
  if (!m) return true; // no status → offline / DNS / TLS
  const code = Number(m[1]);
  return code >= 500 || code === 429;
}

// Minimal HTTP send. We parse the URL with GLib.UriFlags.ENCODED so percent-
// escapes in the path survive — calendar ids contain '#' (e.g. holiday
// calendars), and ags/fetch parses with non-ENCODED flags that would decode
// '%23' back to a literal '#', truncating the path at the fragment (→ 400).
function httpSend(
  method: string,
  url: string,
  headers: Record<string, string>,
  body?: string,
): Promise<{ status: number; text: string }> {
  const session = new Soup.Session();
  const msg = new Soup.Message({
    method,
    uri: GLib.Uri.parse(url, GLib.UriFlags.ENCODED),
  });
  const reqHeaders = msg.get_request_headers();
  for (const [k, v] of Object.entries(headers)) reqHeaders.append(k, v);
  if (body != null)
    msg.set_request_body_from_bytes(
      "application/json",
      new GLib.Bytes(new TextEncoder().encode(body)),
    );
  return new Promise((resolve, reject) => {
    session.send_and_read_async(msg, GLib.PRIORITY_DEFAULT, null, (_s, res) => {
      try {
        const bytes = session.send_and_read_finish(res);
        const data = bytes?.get_data();
        resolve({
          status: msg.get_status(),
          text: data ? new TextDecoder().decode(data) : "",
        });
      } catch (e) {
        reject(e);
      }
    });
  });
}

// Authenticated request: bearer token + one retry on 401 (accessTokenFor
// refreshes), throwing on non-2xx. Returns the raw response body.
async function authedSend(
  email: string,
  method: string,
  url: string,
  body?: string,
  extraHeaders?: Record<string, string>,
): Promise<string> {
  const call = async (force = false) => {
    const token = await accessTokenFor(email, force);
    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
      ...extraHeaders,
    };
    if (body != null) headers["Content-Type"] = "application/json";
    return httpSend(method, url, headers, body);
  };
  let res = await call();
  if (res.status === 401) res = await call(true); // force a token refresh
  if (res.status < 200 || res.status >= 300)
    throw new Error(`${method} ${url} → ${res.status}: ${res.text}`);
  return res.text;
}

// Subset of a CalendarList entry we consume.
export interface GCalendar {
  id: string;
  summary: string;
  primary?: boolean;
  colorId?: string;
  backgroundColor?: string;
  foregroundColor?: string;
  accessRole?: string;
  selected?: boolean;
  defaultReminders?: { method?: string; minutes?: number }[];
}

// Subset of an Events resource (singleEvents=true → occurrences are pre-expanded).
export interface GEvent {
  id: string;
  etag?: string; // version tag, for optimistic-concurrency writes (If-Match)
  status?: string;
  summary?: string;
  description?: string;
  location?: string;
  start?: { date?: string; dateTime?: string; timeZone?: string };
  end?: { date?: string; dateTime?: string; timeZone?: string };
  attendees?: {
    email?: string;
    responseStatus?: string;
    self?: boolean;
    optional?: boolean;
  }[];
  recurringEventId?: string;
  recurrence?: string[]; // RRULE/EXDATE lines (on the series base, not instances)
  transparency?: string;
  visibility?: string;
  colorId?: string;
  hangoutLink?: string; // the Google Meet URL, when the event has one
  conferenceData?: {
    entryPoints?: { entryPointType?: string; uri?: string; label?: string }[];
    conferenceId?: string;
    status?: { statusCode?: string };
  };
  reminders?: {
    useDefault?: boolean;
    overrides?: { method?: string; minutes?: number }[];
  };
}

// The Google Meet join URL for an event, from either field Google returns.
export const meetLinkOf = (g: GEvent): string | undefined =>
  g.hangoutLink ||
  g.conferenceData?.entryPoints?.find((e) => e.entryPointType === "video")?.uri;

// --- response parsing (lightweight runtime guards at the Google boundary) ----

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`bad JSON from Google: ${text.slice(0, 200)}`);
  }
}
const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const asObj = (v: unknown): Record<string, unknown> => {
  if (!isObj(v)) throw new Error("expected a JSON object from Google");
  return v;
};
const asArray = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
// A created/moved event response: we rely on its id (for re-keying), so validate.
function asGEvent(v: unknown): GEvent {
  const o = asObj(v);
  if (typeof o.id !== "string")
    throw new Error("event response missing a string id");
  return o as unknown as GEvent;
}

const authedGet = async (email: string, url: string): Promise<unknown> =>
  parseJson(await authedSend(email, "GET", url));

const PEOPLE_BASE = "https://people.googleapis.com/v1";

export interface GContact {
  name: string;
  email: string;
  photo?: string; // profile picture URL (if the contact has one)
}

// Search the signed-in user's contacts for a query string. Returns up to 10
// name+email(+photo) entries, skipping entries with no email address.
export async function searchContacts(
  email: string,
  query: string,
): Promise<GContact[]> {
  const params = new URLSearchParams({
    query,
    readMask: "names,emailAddresses,photos",
    pageSize: "10",
  });
  const data = asObj(
    await authedGet(email, `${PEOPLE_BASE}/people:searchContacts?${params}`),
  ) as {
    results?: {
      person?: {
        names?: { displayName?: string }[];
        emailAddresses?: { value?: string }[];
        photos?: { url?: string; default?: boolean }[];
      };
    }[];
  };
  const out: GContact[] = [];
  for (const r of data.results ?? []) {
    const p = r.person;
    const addr = p?.emailAddresses?.[0]?.value;
    if (!addr) continue;
    // Skip Google's generic silhouette placeholder (default: true).
    const photo = p?.photos?.find((ph) => ph.url && !ph.default)?.url;
    out.push({
      name: p?.names?.[0]?.displayName ?? "",
      email: addr,
      ...(photo ? { photo } : {}),
    });
  }
  return out;
}

// Search the Workspace directory (colleagues not in personal contacts). Requires
// the directory.readonly scope; only returns results for Workspace accounts.
export async function searchDirectory(
  email: string,
  query: string,
): Promise<GContact[]> {
  const params = new URLSearchParams({
    query,
    readMask: "names,emailAddresses,photos",
    sources: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE",
    pageSize: "10",
  });
  const data = asObj(
    await authedGet(
      email,
      `${PEOPLE_BASE}/people:searchDirectoryPeople?${params}`,
    ),
  ) as {
    people?: {
      names?: { displayName?: string }[];
      emailAddresses?: { value?: string }[];
      photos?: { url?: string; default?: boolean }[];
    }[];
  };
  const out: GContact[] = [];
  for (const p of data.people ?? []) {
    const addr = p.emailAddresses?.[0]?.value;
    if (!addr) continue;
    const photo = p.photos?.find((ph) => ph.url && !ph.default)?.url;
    out.push({
      name: p.names?.[0]?.displayName ?? "",
      email: addr,
      ...(photo ? { photo } : {}),
    });
  }
  return out;
}

export interface BusyInterval {
  start: number; // fractional hour (e.g. 9.5 = 09:30)
  end: number;
  date: string; // YYYY-MM-DD in local time — used to filter per day column
}

// Query the Google Calendar freebusy API for a set of attendee emails over a
// date window. Returns a map of email → busy intervals (local wall-clock hours)
// for the visible window. Intervals that span midnight are split at 24.0.
export async function queryFreeBusy(
  email: string,
  attendees: string[],
  from: Date,
  to: Date,
): Promise<Map<string, BusyInterval[]>> {
  const body = JSON.stringify({
    timeMin: from.toISOString(),
    timeMax: to.toISOString(),
    items: attendees.map((id) => ({ id })),
  });
  const raw = asObj(
    parseJson(await authedSend(email, "POST", `${BASE}/freeBusy`, body)),
  );
  const calendars = isObj(raw.calendars) ? raw.calendars : {};
  const result = new Map<string, BusyInterval[]>();
  for (const attendee of attendees) {
    const entry = isObj(calendars[attendee]) ? calendars[attendee] : {};
    // This account can't see the attendee's calendar (e.g. a personal account
    // querying a Workspace colleague) — omit so a caller can try another.
    if (asArray(entry.errors).length) continue;
    const busy = asArray(entry.busy);
    const intervals: BusyInterval[] = [];
    for (const slot of busy) {
      if (!isObj(slot)) continue;
      const s = new Date(slot.start as string);
      const e = new Date(slot.end as string);
      const startH = s.getHours() + s.getMinutes() / 60;
      const endH = e.getHours() + e.getMinutes() / 60;
      const pad = (n: number) => String(n).padStart(2, "0");
      const date = `${s.getFullYear()}-${pad(s.getMonth() + 1)}-${pad(s.getDate())}`;
      // Split cross-midnight spans: clamp the start-day portion to 24.
      intervals.push({ start: startH, end: endH > startH ? endH : 24, date });
    }
    result.set(attendee, intervals);
  }
  return result;
}

// The IANA timezone of a calendar (calId == an attendee's email for their
// primary calendar), if `email`'s account can see it. Returns null on no access.
export async function getCalendarTimezone(
  email: string,
  calId: string,
): Promise<string | null> {
  const url = `${BASE}/calendars/${encodeURIComponent(calId)}`;
  try {
    const data = asObj(parseJson(await authedSend(email, "GET", url)));
    return typeof data.timeZone === "string" ? data.timeZone : null;
  } catch {
    return null;
  }
}

// --- writes -----------------------------------------------------------------

const eventsBase = (calId: string) =>
  `${BASE}/calendars/${encodeURIComponent(calId)}/events`;

// Create an event; returns the created resource (with its Google id).
export async function insertEvent(
  email: string,
  calId: string,
  body: object,
  sendUpdates = false,
): Promise<GEvent> {
  const url = sendUpdates
    ? `${eventsBase(calId)}?sendUpdates=all`
    : eventsBase(calId);
  return asGEvent(
    parseJson(await authedSend(email, "POST", url, JSON.stringify(body))),
  );
}

// Full-text search a calendar (Google's `q` matches summary, description,
// location, attendees, …), bounded to roughly ±2 years around now. orderBy=
// startTime returns matches oldest-first, so without a window the result cap
// would be consumed by ancient events and never reach the imminent one (it also
// finds events outside the synced ±1yr cache). The caller re-sorts by proximity.
export async function searchEvents(
  email: string,
  calId: string,
  query: string,
): Promise<GEvent[]> {
  const now = new Date();
  const min = new Date(now);
  min.setFullYear(min.getFullYear() - 2);
  const max = new Date(now);
  max.setFullYear(max.getFullYear() + 2);
  const params = new URLSearchParams({
    q: query,
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "250",
    showDeleted: "false",
    timeMin: min.toISOString(),
    timeMax: max.toISOString(),
  });
  const url = `${eventsBase(calId)}?${params.toString()}`;
  const data = asObj(await authedGet(email, url));
  const out: GEvent[] = [];
  for (const e of asArray(data.items))
    if (isObj(e) && typeof e.id === "string") out.push(e as unknown as GEvent);
  return out;
}

// Attach a Google Meet conference to an event (conferenceDataVersion=1 is
// required for conferenceData writes). The requestId is keyed to the event so a
// retry is idempotent. Returns the updated event (its hangoutLink/conferenceData
// is usually populated synchronously).
export async function addMeet(
  email: string,
  calId: string,
  gid: string,
): Promise<GEvent> {
  const body = JSON.stringify({
    conferenceData: {
      createRequest: {
        requestId: `meet-${gid}`.slice(0, 64),
        conferenceSolutionKey: { type: "hangoutsMeet" },
      },
    },
  });
  const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}?conferenceDataVersion=1`;
  return asGEvent(parseJson(await authedSend(email, "PATCH", url, body)));
}

// Fetch a single event by id (no singleEvents expansion), so a recurring
// series' base returns its `recurrence` (RRULE) — used to show the real repeat
// rule in the editor and to split a series for "this and following" edits.
export async function getEvent(
  email: string,
  calId: string,
  gid: string,
): Promise<GEvent> {
  const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}`;
  return asGEvent(parseJson(await authedSend(email, "GET", url)));
}

// All instances of a recurring series (the dedicated instances endpoint, with
// originalStartTime populated). Used to count how many occurrences survive a
// "this and following" split so a COUNT-bounded rule keeps the right length.
export async function listInstances(
  email: string,
  calId: string,
  gid: string,
): Promise<GEvent[]> {
  const events: GEvent[] = [];
  let pageToken: string | undefined;
  do {
    const params = new URLSearchParams({ maxResults: "2500" });
    if (pageToken) params.set("pageToken", pageToken);
    const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}/instances?${params}`;
    const data = asObj(await authedGet(email, url));
    for (const e of asArray(data.items))
      if (isObj(e) && typeof e.id === "string")
        events.push(e as unknown as GEvent);
    pageToken =
      typeof data.nextPageToken === "string" ? data.nextPageToken : undefined;
  } while (pageToken);
  return events;
}

// One sync pass over a calendar. With a `syncToken` it returns only the changes
// since that token (incremental, all-time — Google forbids timeMin/timeMax with a
// token); otherwise a bounded initial fetch. `singleEvents` must match between the
// two or Google 400s. A 410 means the token expired → caller must do a full sync.
// `nextSyncToken` (on the last page) is persisted for the next incremental pass.
export interface SyncPage {
  events: GEvent[]; // incremental pages include cancellations (status "cancelled")
  nextSyncToken?: string;
  expired: boolean;
}

export async function syncEvents(
  email: string,
  calId: string,
  opts: { syncToken?: string; timeMin?: Date; timeMax?: Date },
): Promise<SyncPage> {
  const events: GEvent[] = [];
  let pageToken: string | undefined;
  let nextSyncToken: string | undefined;
  do {
    const params = new URLSearchParams({
      singleEvents: "true",
      maxResults: "2500",
    });
    if (opts.syncToken) {
      params.set("syncToken", opts.syncToken);
    } else {
      params.set("timeMin", opts.timeMin!.toISOString());
      params.set("timeMax", opts.timeMax!.toISOString());
      params.set("showDeleted", "false");
    }
    if (pageToken) params.set("pageToken", pageToken);
    const url = `${BASE}/calendars/${encodeURIComponent(calId)}/events?${params.toString()}`;
    let data;
    try {
      data = asObj(await authedGet(email, url));
    } catch (err) {
      // 410 GONE → the sync token is no longer valid; signal a full resync.
      if (opts.syncToken && /→ 410\b/.test(String(err)))
        return { events: [], expired: true };
      throw err;
    }
    for (const e of asArray(data.items))
      if (isObj(e) && typeof e.id === "string")
        events.push(e as unknown as GEvent);
    pageToken =
      typeof data.nextPageToken === "string" ? data.nextPageToken : undefined;
    if (typeof data.nextSyncToken === "string")
      nextSyncToken = data.nextSyncToken;
  } while (pageToken);
  return { events, nextSyncToken, expired: false };
}

// Patch a subset of an event's fields. With `ifMatch` (an etag) the write is
// rejected with 412 if the event changed server-side since — the caller refreshes
// and retries. Returns the new etag so the caller can keep its copy current.
export async function patchEvent(
  email: string,
  calId: string,
  gid: string,
  body: object,
  sendUpdates = false,
  ifMatch?: string,
): Promise<string | undefined> {
  const qs = sendUpdates ? "?sendUpdates=all" : "";
  const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}${qs}`;
  const text = await authedSend(
    email,
    "PATCH",
    url,
    JSON.stringify(body),
    ifMatch ? { "If-Match": ifMatch } : undefined,
  );
  const o = parseJson(text);
  return isObj(o) && typeof o.etag === "string" ? o.etag : undefined;
}

export async function deleteEvent(
  email: string,
  calId: string,
  gid: string,
  sendUpdates = false,
  ifMatch?: string,
): Promise<void> {
  const qs = sendUpdates ? "?sendUpdates=all" : "";
  const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}${qs}`;
  await authedSend(
    email,
    "DELETE",
    url,
    undefined,
    ifMatch ? { "If-Match": ifMatch } : undefined,
  );
}

// Move an event to another calendar; returns the moved resource (new calendar,
// same event id).
export async function moveEvent(
  email: string,
  calId: string,
  gid: string,
  destCalId: string,
): Promise<GEvent> {
  const url = `${eventsBase(calId)}/${encodeURIComponent(gid)}/move?destination=${encodeURIComponent(destCalId)}`;
  return asGEvent(parseJson(await authedSend(email, "POST", url, undefined)));
}

export async function listCalendars(email: string): Promise<GCalendar[]> {
  const data = asObj(await authedGet(email, `${BASE}/users/me/calendarList`));
  return asArray(data.items).filter(
    (c): c is GCalendar =>
      isObj(c) && typeof c.id === "string" && typeof c.summary === "string",
  );
}

// All events on `calId` in [timeMin, timeMax). Recurring events are expanded
// into single occurrences and the result is paginated through.
export async function listEvents(
  email: string,
  calId: string,
  timeMin: Date,
  timeMax: Date,
): Promise<GEvent[]> {
  const events: GEvent[] = [];
  let pageToken: string | undefined;
  do {
    const params = new URLSearchParams({
      singleEvents: "true",
      orderBy: "startTime",
      timeMin: timeMin.toISOString(),
      timeMax: timeMax.toISOString(),
      maxResults: "2500",
      showDeleted: "false",
    });
    if (pageToken) params.set("pageToken", pageToken);
    const url = `${BASE}/calendars/${encodeURIComponent(calId)}/events?${params.toString()}`;
    const data = asObj(await authedGet(email, url));
    for (const e of asArray(data.items))
      if (isObj(e) && typeof e.id === "string")
        events.push(e as unknown as GEvent);
    pageToken =
      typeof data.nextPageToken === "string" ? data.nextPageToken : undefined;
  } while (pageToken);
  return events;
}

// Set a calendar's color in the user's calendarList — a per-user display setting
// (allowed even for read-only calendars). colorRgbFormat=true sets the exact hex.
export async function setCalendarColor(
  email: string,
  calId: string,
  bg: string,
  fg: string,
): Promise<void> {
  const url = `${BASE}/users/me/calendarList/${encodeURIComponent(calId)}?colorRgbFormat=true`;
  const body = JSON.stringify({ backgroundColor: bg, foregroundColor: fg });
  await authedSend(email, "PATCH", url, body);
}
