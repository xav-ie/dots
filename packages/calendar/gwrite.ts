// Write-mapping: app event/field → Google Calendar request bodies. The inverse
// of gmap.ts's read-mapping. Used by store.ts to push edits/creates to Google.
import type { CalEvent } from "./data";
import { eventColorId, type Color } from "./palette";
import { parseRecur, type Recur } from "./recur";

const pad = (n: number) => String(n).padStart(2, "0");

// A local wall-clock Date for `hours` on `date` ([y, m0, d]).
const at = (date: [number, number, number], hours: number) =>
  new Date(
    date[0],
    date[1],
    date[2],
    Math.floor(hours),
    Math.round((hours - Math.floor(hours)) * 60),
  );

const ymd = (d: Date) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// start/end body. All-day uses dates (Google's end date is exclusive → +1 day);
// timed uses UTC instants (the local wall-clock converted via toISOString) plus
// the event's IANA `timeZone` when set. The end day is `ev.endDate` (a multi-day
// span) or the start day. `allDay` is passed explicitly — mapped all-day events
// live in ALL_DAY without `ev.allDay`/`start`/`end`, so the flag isn't reliable.
// `clearOther` nulls the opposite field (date↔dateTime) when toggling an event
// between all-day and timed — Google's patch doesn't auto-clear it, and an event
// with both `date` and `dateTime` is rejected ("Invalid start time").
export function startEndBody(
  ev: CalEvent,
  allDay: boolean,
  clearOther = false,
): { start: object; end: object } {
  const date = ev.date ?? [
    new Date().getFullYear(),
    new Date().getMonth(),
    new Date().getDate(),
  ];
  const endDate = ev.endDate ?? date; // end day defaults to the start day
  if (allDay) {
    // Google's end.date is EXCLUSIVE → the day after the inclusive last day.
    const next = new Date(endDate[0], endDate[1], endDate[2] + 1);
    const clr = clearOther ? { dateTime: null } : {};
    return {
      start: { date: ymd(at(date, 0)), ...clr },
      end: { date: ymd(next), ...clr },
    };
  }
  const tz = ev.timezone ? { timeZone: ev.timezone } : {};
  const clr = clearOther ? { date: null } : {};
  return {
    start: { dateTime: at(date, ev.start ?? 0).toISOString(), ...tz, ...clr },
    end: { dateTime: at(endDate, ev.end ?? 1).toISOString(), ...tz, ...clr },
  };
}

// Links have no arbitrary-URL field in the Calendar API (native attachments are
// Drive-only), so we fold them into the description as a trailing block.
// splitDescription (gmap.ts reads it back) is the exact inverse. `links` is
// NEWLINE-separated end to end — URLs can legally contain commas (maps, query
// params), so a comma delimiter would corrupt them.
const LINKS_HEADER = "Links:";
const URLISH = /^(https?:\/\/)?([\w-]+\.)+[\w-]{2,}(\/\S*)?$/i;

export function combineDescription(desc?: string, links?: string): string {
  const base = (desc ?? "").trimEnd();
  const urls = (links ? links.split("\n") : [])
    .map((s) => s.trim())
    .filter(Boolean);
  if (!urls.length) return base;
  const block = [LINKS_HEADER, ...urls].join("\n");
  return base ? `${base}\n\n${block}` : block;
}

// Pull a trailing "Links:" block (header + URL-only lines to EOF) back out of a
// Google description into { description, links }. Anything else is left intact.
// We only treat it as our block when the header is at the start or preceded by a
// blank line (combineDescription always emits `\n\n`), so a user's prose that
// happens to end "Links:\nsome.domain" isn't misread as machine data.
export function splitDescription(raw?: string): {
  description?: string;
  links?: string;
} {
  if (!raw) return {};
  const lines = raw.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim() !== LINKS_HEADER) continue;
    if (i !== 0 && lines[i - 1].trim() !== "") break; // not our generated block
    const after = lines
      .slice(i + 1)
      .map((l) => l.trim())
      .filter(Boolean);
    if (after.length && after.every((l) => URLISH.test(l)))
      return {
        description: lines.slice(0, i).join("\n").trimEnd() || undefined,
        links: after.join("\n"),
      };
    break;
  }
  return { description: raw };
}

const attendees = (csv?: string) =>
  (csv ? csv.split(",").filter(Boolean) : []).map((email) => ({ email }));

function recurrence(json?: string): string[] | null {
  if (!json) return null;
  const r = parseRecur(json);
  return r ? [rrule(r)] : null;
}

const DAY_NUM: Record<string, number> = {
  SU: 0,
  MO: 1,
  TU: 2,
  WE: 3,
  TH: 4,
  FR: 5,
  SA: 6,
};

// Parse a Google `recurrence` array (the RRULE line) back into our Recur model,
// so the editor can show a synced series' real repeat rule. Inverse of rrule().
export function parseRRULE(lines?: string[]): Recur | null {
  const line = lines?.find((l) => l.startsWith("RRULE"));
  if (!line) return null;
  const kv: Record<string, string> = {};
  for (const part of line.replace(/^RRULE:/, "").split(";")) {
    const [k, v] = part.split("=");
    if (k && v) kv[k] = v;
  }
  const FREQ: Record<string, Recur["freq"]> = {
    DAILY: "day",
    WEEKLY: "week",
    MONTHLY: "month",
    YEARLY: "year",
  };
  const freq = FREQ[kv.FREQ];
  if (!freq) return null;
  const r: Recur = { freq, interval: kv.INTERVAL ? Number(kv.INTERVAL) : 1 };
  if (kv.BYDAY) {
    const tokens = kv.BYDAY.split(",");
    if (freq === "week")
      r.weekdays = tokens
        .map((t) => DAY_NUM[t.replace(/^[+-]?\d/, "")])
        .filter((n): n is number => n != null);
    else if (freq === "month" && /\d/.test(kv.BYDAY)) r.monthByWeekday = true;
  }
  if (kv.COUNT) r.ends = { type: "after", count: Number(kv.COUNT) };
  else if (kv.UNTIL) {
    const m = kv.UNTIL.match(/^(\d{4})(\d{2})(\d{2})/);
    if (m)
      r.ends = { type: "on", until: `${m[1]}-${Number(m[2]) - 1}-${m[3]}` };
  } else r.ends = { type: "never" };
  return r;
}

// Rewrite a COUNT-bounded rule to a new count (the post-split series should keep
// only the occurrences that survive, not restart the full count). No-op if the
// rule isn't count-bounded.
export function rewriteCount(lines: string[], n: number): string[] {
  return lines.map((l) =>
    l.startsWith("RRULE") && /COUNT=\d+/.test(l)
      ? l.replace(/COUNT=\d+/, `COUNT=${Math.max(1, n)}`)
      : l,
  );
}

// Truncate a series so it ends just before `occurrenceStart` — used to split a
// recurring event for "this and following": the old series gets an UNTIL right
// before this occurrence, with any COUNT dropped (UNTIL supersedes it). UNTIL is
// computed from the occurrence's exact instant minus 1s in UTC (date form for
// all-day) — a calendar-day-minus-1 boundary can wrongly keep/drop the boundary
// occurrence when a timezone offset moves its UTC date.
export function recurrenceUntil(
  lines: string[] | undefined,
  occurrenceStart: Date,
  allDay: boolean,
): string[] {
  const line = lines?.find((l) => l.startsWith("RRULE")) ?? "RRULE:FREQ=DAILY";
  let until: string;
  if (allDay) {
    const o = occurrenceStart;
    const prev = new Date(o.getFullYear(), o.getMonth(), o.getDate() - 1);
    until = `${prev.getFullYear()}${pad(prev.getMonth() + 1)}${pad(prev.getDate())}`;
  } else {
    const t = new Date(occurrenceStart.getTime() - 1000);
    until =
      `${t.getUTCFullYear()}${pad(t.getUTCMonth() + 1)}${pad(t.getUTCDate())}` +
      `T${pad(t.getUTCHours())}${pad(t.getUTCMinutes())}${pad(t.getUTCSeconds())}Z`;
  }
  const parts = line
    .replace(/^RRULE:/, "")
    .split(";")
    .filter((p) => p && !/^(UNTIL|COUNT)=/.test(p));
  parts.push(`UNTIL=${until}`);
  return [`RRULE:${parts.join(";")}`];
}

function rrule(r: Recur): string {
  const FREQ = {
    day: "DAILY",
    week: "WEEKLY",
    month: "MONTHLY",
    year: "YEARLY",
  };
  const parts = [`FREQ=${FREQ[r.freq]}`, `INTERVAL=${r.interval}`];
  if (r.freq === "week" && r.weekdays?.length) {
    const D = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
    parts.push(`BYDAY=${r.weekdays.map((d) => D[d]).join(",")}`);
  }
  if (r.ends?.type === "after" && r.ends.count)
    parts.push(`COUNT=${r.ends.count}`);
  if (r.ends?.type === "on" && r.ends.until) {
    const [y, m, d] = r.ends.until.split("-").map(Number); // m is 0-based
    parts.push(`UNTIL=${y}${pad(m + 1)}${pad(d)}T235959Z`);
  }
  return `RRULE:${parts.join(";")}`;
}

const visibility = (v: string) =>
  v === "Public" ? "public" : v === "Private" ? "private" : "default";

// Reminders patch body: explicit popup overrides, unless the event defers to the
// calendar defaults (useDefault). An empty `reminders` with useDefault=false
// clears all reminders.
export function remindersBody(ev: CalEvent): object {
  if (ev.useDefaultReminders !== false)
    return { reminders: { useDefault: true } };
  return {
    reminders: {
      useDefault: false,
      overrides: (ev.reminders ?? []).map((m) => ({
        method: "popup",
        minutes: m,
      })),
    },
  };
}

// Patch body for a single edited field. Returns null for fields store.ts routes
// elsewhere: calendar → move; timezone → startEndBody; description/links →
// combineDescription; status stays local (no RSVP write yet).
export function fieldBody(field: keyof CalEvent, value: string): object | null {
  switch (field) {
    case "title":
      return { summary: value };
    case "description":
      return { description: value };
    case "address":
      return { location: value };
    case "color": {
      const cid = eventColorId(value as Color);
      return cid ? { colorId: cid } : null;
    }
    case "participants":
      return { attendees: attendees(value) };
    case "freeBusy":
      return { transparency: value === "Free" ? "transparent" : "opaque" };
    case "visibility":
      return { visibility: visibility(value) };
    case "recur":
      return { recurrence: recurrence(value) };
    default:
      return null;
  }
}

// Full body for creating an event.
export function eventBody(ev: CalEvent, allDay: boolean): object {
  const body: Record<string, unknown> = {
    summary: ev.title || "New event",
    ...startEndBody(ev, allDay),
  };
  const desc = combineDescription(ev.description, ev.links);
  if (desc) body.description = desc;
  if (ev.address) body.location = ev.address;
  // Only set colorId for an explicit event-color override; otherwise the event
  // inherits its calendar's color.
  const cid = ev.color ? eventColorId(ev.color) : undefined;
  if (cid) body.colorId = cid;
  if (ev.participants) body.attendees = attendees(ev.participants);
  if (ev.freeBusy === "Free") body.transparency = "transparent";
  if (ev.visibility && ev.visibility !== "Default visibility")
    body.visibility = visibility(ev.visibility);
  const rec = recurrence(ev.recur);
  if (rec) body.recurrence = rec;
  // Only send reminders when the event overrides the calendar defaults.
  if (ev.useDefaultReminders === false) Object.assign(body, remindersBody(ev));
  return body;
}
