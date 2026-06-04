// Dummy data for the UI pass, keyed to real dates so week/day navigation and
// the mini-calendar work. Each event either lands on a specific `date`
// ([year, month0, day]) or recurs weekly on `weekdays` (0 = Sun). Swapping in a
// live backend later means replacing eventsOn/allDayOn, not the UI.

// The palette (the Color union, names, default) is defined once in palette.ts;
// re-exported here for the many existing `from "./data"` imports.
import { DEFAULT_COLOR, toEventColor, type Color } from "./palette";
import { gmtLabel, offsetMinutes } from "./datetime";
export { DEFAULT_COLOR, type Color };

export interface CalEvent {
  id?: string; // stable id for persistence (assigned below)
  title: string;
  start: number; // hours, 13.5 = 1:30 PM
  end: number;
  color?: Color; // event-color OVERRIDE; unset = inherit the calendar's color
  location?: string; // the time label shown under the title in the grid chip
  calendar?: string; // owning calendar (editable / persisted)
  address?: string; // real location (editable / persisted)
  description?: string; // editable / persisted
  // Side-by-side packing for overlapping events.
  col?: number;
  cols?: number;
  selected?: boolean;
  allDay?: boolean;
  freeBusy?: string; // "Busy" | "Free"
  visibility?: string; // "Default visibility" | "Public" | "Private"
  timezone?: string; // IANA zone id (e.g. "America/New_York"); unset = system tz
  status?: "accepted" | "invited" | "maybe" | "declined"; // RSVP (default accepted)
  participants?: string; // comma-separated emails
  // Each attendee's RSVP, email → status, for the participant-list indicators.
  attendeeStatus?: Record<
    string,
    "accepted" | "invited" | "maybe" | "declined"
  >;
  // Attendees marked optional (email → true); rendered dimmed in the list.
  optional?: Record<string, boolean>;
  links?: string; // newline-separated link URLs (folded into the Google description)
  meetLink?: string; // Google Meet join URL, when the event has a conference
  etag?: string; // Google version tag, sent as If-Match to guard concurrent writes
  recur?: string; // recurrence config as JSON (see recur.ts); null = no repeat
  // The series' base event gid when this is one occurrence of a recurring event
  // (singleEvents expands the series). Drives the edit/delete scope dialog.
  recurringEventId?: string;
  // Popup reminders, in minutes before the event. When useDefaultReminders is
  // true (or both are unset) the calendar's defaults apply instead; an explicit
  // `reminders` list (with useDefaultReminders=false) overrides them.
  reminders?: number[];
  useDefaultReminders?: boolean;
  // Transient: a synthesized busy-preview block (an invitee's freebusy interval)
  // laid out alongside real events. Non-interactive; never persisted.
  busy?: boolean;
  // Occurrence: one of these.
  date?: [number, number, number];
  // Inclusive last day for a multi-day all-day event (spans date..endDate).
  endDate?: [number, number, number];
  weekdays?: number[];
}

const BIRTHDAY_RE = /birth\s*day/i;
export const isBirthday = (title: string) => BIRTHDAY_RE.test(title);

// Whether an event repeats — a synced occurrence (recurringEventId), one with a
// local recurrence rule, or a weekday-recurring seed. Drives the ↻ chip glyph.
export const isRecurringEvent = (e: {
  recurringEventId?: string;
  recur?: string;
  weekdays?: number[];
}): boolean => !!(e.recurringEventId || e.recur || e.weekdays?.length);

export interface AllDayEvent {
  id?: string;
  title: string;
  color?: Color; // event-color OVERRIDE; unset = inherit the calendar's color
  calendar?: string;
  address?: string;
  description?: string;
  links?: string; // newline-separated link URLs (folded into the Google description)
  recurringEventId?: string; // series base gid when this is a recurring occurrence
  etag?: string; // Google version tag (If-Match)
  reminders?: number[]; // popup minutes-before (see CalEvent)
  useDefaultReminders?: boolean;
  date: [number, number, number];
  endDate?: [number, number, number]; // inclusive last day for a multi-day span
}

// Represent an all-day event as a CalEvent for list/search/grid rendering (which
// expects start/end); `allDay` flags it so the row shows "All day", not a time.
// Accepts an already-CalEvent too (a timed event flipped to all-day).
export const allDayAsCalEvent = (a: AllDayEvent | CalEvent): CalEvent => ({
  id: a.id,
  title: a.title,
  color: a.color,
  calendar: a.calendar,
  address: a.address,
  description: a.description,
  links: a.links,
  recurringEventId: a.recurringEventId,
  start: 0,
  end: 0,
  allDay: true,
  date: a.date ?? [0, 0, 0],
  endDate: a.endDate,
});

const MAY = (d: number): [number, number, number] => [2026, 4, d];

export const ALL_DAY: AllDayEvent[] = [
  { title: "Memorial Day", color: "tomato", date: MAY(25) },
  { title: "Alex's birthday", color: "tomato", date: MAY(25) },
  { title: "Sam's birthday", color: "tomato", date: MAY(29) },
  { title: "Payday", color: "tomato", date: MAY(29) },
];

export const EVENTS: CalEvent[] = [
  // Recurring workout, weekday mornings — also fills other weeks.
  {
    title: "Workout",
    start: 8,
    end: 8.5,
    color: "graphite",
    weekdays: [1, 2, 3, 4, 5],
  },

  // Mon 25
  {
    title: "Vendor Sync",
    start: 11.5,
    end: 12.5,
    color: "graphite",
    location: "11:30 AM–12:30 PM",
    date: MAY(25),
  },
  {
    title: "Sprint Planning",
    start: 13,
    end: 14,
    color: "cobalt",
    col: 0,
    cols: 2,
    location: "1–2 PM",
    date: MAY(25),
    participants: "sam@example.com,alex@example.com,jordan@example.com",
  },
  {
    title: "Daily Standup",
    start: 13,
    end: 14,
    color: "cobalt",
    col: 1,
    cols: 2,
    date: MAY(25),
  },
  {
    title: "Team Call",
    start: 13.5,
    end: 14.5,
    color: "cobalt",
    location: "1:30–2:30 PM",
    date: MAY(25),
  },

  // Tue 26
  {
    title: "Client Kickoff",
    start: 12.5,
    end: 13.25,
    color: "graphite",
    date: MAY(26),
    status: "invited",
  },
  {
    title: "Daily Standup",
    start: 13,
    end: 14,
    color: "cobalt",
    location: "1–2 PM",
    date: MAY(26),
  },
  {
    title: "Tech Review",
    start: 15,
    end: 15.75,
    color: "graphite",
    location: "3–3:45 PM",
    date: MAY(26),
    status: "maybe",
  },

  // Wed 27
  {
    title: "Focus time",
    start: 9,
    end: 11,
    color: "cobalt",
    location: "9–11 AM",
    date: MAY(27),
  },
  {
    title: "Daily Standup",
    start: 13,
    end: 14,
    color: "cobalt",
    location: "1–2 PM",
    date: MAY(27),
  },
  {
    title: "Team Call",
    start: 15,
    end: 16,
    color: "cobalt",
    location: "3–4 PM",
    date: MAY(27),
  },

  // Thu 28
  {
    title: "Accessibility Review",
    start: 10.5,
    end: 11,
    color: "grape",
    location: "10:30 AM",
    date: MAY(28),
  },
  {
    title: "Daily Standup",
    start: 13,
    end: 14,
    color: "cobalt",
    location: "1–2 PM",
    date: MAY(28),
  },
  {
    title: "Product Demo",
    start: 13.5,
    end: 14,
    color: "cobalt",
    location: "1:30 PM",
    date: MAY(28),
  },

  // Fri 29
  {
    title: "Dentist",
    start: 9,
    end: 10,
    color: "basil",
    col: 0,
    cols: 2,
    location: "9–10 AM",
    date: MAY(29),
  },
  {
    title: "Ortho",
    start: 9,
    end: 10,
    color: "eucalyptus",
    col: 1,
    cols: 2,
    location: "9 AM",
    date: MAY(29),
  },
  {
    title: "Club Organizers Chat",
    start: 11,
    end: 12,
    color: "grape",
    location: "11 AM–12 PM",
    date: MAY(29),
  },
  {
    title: "Daily Standup",
    start: 13,
    end: 14,
    color: "cobalt",
    location: "1 PM",
    date: MAY(29),
  },
  {
    title: "Code Freeze",
    start: 14,
    end: 15,
    color: "graphite",
    col: 0,
    cols: 2,
    location: "2–3 PM",
    date: MAY(29),
  },
  {
    title: "Sprint Review",
    start: 14,
    end: 14.75,
    color: "cobalt",
    col: 1,
    cols: 2,
    location: "2–2:45 PM",
    date: MAY(29),
  },
];

const dayNum = (y: number, m: number, d: number) => new Date(y, m, d).getTime();

type Span = {
  date?: [number, number, number];
  endDate?: [number, number, number];
};

// `span` honors a multi-day endDate (all-day chips span days; timed events stay
// on their start day, since the time grid can't lay one chip across columns).
function occursOn(
  e: Span & { weekdays?: number[] },
  d: Date,
  span = true,
): boolean {
  if (e.date) {
    const day = dayNum(d.getFullYear(), d.getMonth(), d.getDate());
    const start = dayNum(e.date[0], e.date[1], e.date[2]);
    const end =
      span && e.endDate
        ? dayNum(e.endDate[0], e.endDate[1], e.endDate[2])
        : start;
    return day >= start && day <= end;
  }
  return e.weekdays?.includes(d.getDay()) ?? false;
}

// Which part of a multi-day span `d` falls on, for continuity styling (rounded
// ends, square middle; the title shows only on the first day).
export function spanPart(e: Span, d: Date): "single" | "start" | "mid" | "end" {
  if (!e.endDate || !e.date) return "single";
  const day = dayNum(d.getFullYear(), d.getMonth(), d.getDate());
  const start = dayNum(e.date[0], e.date[1], e.date[2]);
  const end = dayNum(e.endDate[0], e.endDate[1], e.endDate[2]);
  if (start === end) return "single";
  if (day <= start) return "start";
  if (day >= end) return "end";
  return "mid";
}

// Timed events on day `d`. A multi-day timed event is returned as a per-day
// CLAMPED COPY — start day: start→24, middle days: full, end day: 0→end — so the
// time-grid layout positions each segment correctly. The copy keeps the real id
// (click resolves the real event for the editor) and `endDate` (so resize/drag
// is disabled for segments).
export const eventsOn = (d: Date): CalEvent[] => {
  const out: CalEvent[] = [];
  for (const e of EVENTS) {
    if (e.allDay || !occursOn(e, d, true)) continue;
    const part = spanPart(e, d);
    if (part === "single") {
      out.push(e);
    } else {
      out.push({
        ...e,
        start: part === "start" ? (e.start ?? 0) : 0,
        end: part === "end" ? (e.end ?? 24) : 24,
      });
    }
  }
  return out;
};
// All-day chips: the dedicated all-day events plus any timed event the user has
// flipped to all-day via the editor switch.
export const allDayOn = (d: Date): (AllDayEvent | CalEvent)[] => [
  ...ALL_DAY.filter((e) => occursOn(e, d)),
  ...EVENTS.filter((e) => e.allDay && occursOn(e, d)),
];

// Which sidebar calendar each event belongs to (by title), so hiding a calendar
// removes its events from the grid.
const CAL_OF: Record<string, string> = {
  Workout: "Home",
  "Vendor Sync": "you@work.example",
  "Sprint Planning": "you@work.example",
  "Daily Standup": "you@work.example",
  "Team Call": "you@work.example",
  "Client Kickoff": "Acme Co",
  "Tech Review": "Globex",
  "Focus time": "you@work.example",
  "Accessibility Review": "Acme Co",
  "Product Demo": "you@work.example",
  Dentist: "you@example.com",
  Ortho: "you@example.com",
  "Club Organizers Chat": "Tennis Club Admin",
  "Code Freeze": "you@work.example",
  "Sprint Review": "you@work.example",
  "Memorial Day": "Holidays",
  "Alex's birthday": "Birthdays",
  "Sam's birthday": "Birthdays",
  Payday: "you@work.example",
};
export const calOf = (title: string): string => CAL_OF[title] ?? "";

// Content-derived ids so persisted overrides stay attached to the same event
// even if the seed arrays are reordered (positional `e${i}` ids would drift).
const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
const whenKey = (e: { date?: number[]; weekdays?: number[] }) =>
  e.date ? e.date.join("-") : `w${(e.weekdays ?? []).join("")}`;

EVENTS.forEach((e) => {
  e.id = `e-${slug(e.title)}-${whenKey(e)}-${e.start}`;
  e.calendar = calOf(e.title);
});
ALL_DAY.forEach((e) => {
  e.id = `a-${slug(e.title)}-${whenKey(e)}`;
  e.calendar = calOf(e.title);
});

// Fake per-person availability for the draft-invite busy preview. Recurring by
// weekday so it shows on any week.
interface BusyBlock {
  weekdays: number[];
  start: number;
  end: number;
}
const BUSY: Record<string, BusyBlock[]> = {
  "alex@example.com": [
    { weekdays: [1, 2, 3, 4, 5], start: 10.5, end: 11 },
    { weekdays: [1, 2, 3, 4, 5], start: 11.5, end: 12.5 },
    { weekdays: [1, 3, 5], start: 14, end: 14.75 },
    { weekdays: [1, 2, 3, 4, 5], start: 19, end: 20 },
  ],
  "sam@example.com": [
    { weekdays: [1, 3, 5], start: 9, end: 10 },
    { weekdays: [1, 2, 3, 4, 5], start: 13, end: 14 },
    { weekdays: [2, 4], start: 15, end: 16 },
  ],
  "jordan@example.com": [
    { weekdays: [1, 2, 3, 4, 5], start: 9.5, end: 10.5 },
    { weekdays: [2, 4], start: 16, end: 17 },
  ],
};
const DEFAULT_BUSY: BusyBlock[] = [
  { weekdays: [1, 2, 3, 4, 5], start: 12, end: 13 },
  { weekdays: [1, 2, 3, 4, 5], start: 16, end: 17 },
];

export function personBusy(
  email: string,
  d: Date,
): { start: number; end: number }[] {
  return (BUSY[email] ?? DEFAULT_BUSY)
    .filter((b) => b.weekdays.includes(d.getDay()))
    .map((b) => ({ start: b.start, end: b.end }));
}

// Suggestion lists for the people / location search fields.
export interface Suggestion {
  title: string;
  subtitle: string;
  recent?: boolean;
  // For people from a specific connected account: the account email and a color
  // dot, so the suggestion list shows which account a contact came from.
  source?: string;
  dotColor?: Color;
}

export const PEOPLE: Suggestion[] = [
  { title: "Alex Morgan", subtitle: "alex@example.com", recent: true },
  { title: "Jordan Lee", subtitle: "jordan@example.com", recent: true },
  { title: "Sam Rivera", subtitle: "sam@example.com", recent: true },
  { title: "Jordan Lee", subtitle: "jordan.lee@example.com", recent: true },
  { title: "Taylor Kim", subtitle: "taylor@example.com" },
  { title: "Casey Park", subtitle: "casey@example.com" },
];

// Curated fallback used only if Intl.supportedValuesOf is unavailable.
const TIMEZONES_FALLBACK: Suggestion[] = [
  { title: "GMT−11 Pago Pago", subtitle: "Pacific/Pago_Pago" },
  { title: "GMT−10 Honolulu", subtitle: "Pacific/Honolulu" },
  { title: "GMT−9 Anchorage", subtitle: "America/Anchorage" },
  { title: "GMT−8 Los Angeles", subtitle: "America/Los_Angeles" },
  { title: "GMT−7 Denver", subtitle: "America/Denver" },
  { title: "GMT−7 Phoenix", subtitle: "America/Phoenix" },
  { title: "GMT−6 Chicago", subtitle: "America/Chicago" },
  { title: "GMT−6 Mexico City", subtitle: "America/Mexico_City" },
  { title: "GMT−5 New York", subtitle: "America/New_York" },
  { title: "GMT−5 Toronto", subtitle: "America/Toronto" },
  { title: "GMT−5 Bogotá", subtitle: "America/Bogota" },
  { title: "GMT−4 Halifax", subtitle: "America/Halifax" },
  { title: "GMT−3 São Paulo", subtitle: "America/Sao_Paulo" },
  { title: "GMT−3 Buenos Aires", subtitle: "America/Argentina/Buenos_Aires" },
  { title: "GMT−1 Azores", subtitle: "Atlantic/Azores" },
  { title: "GMT+0 London", subtitle: "Europe/London" },
  { title: "GMT+0 Lisbon", subtitle: "Europe/Lisbon" },
  { title: "GMT+0 Reykjavik", subtitle: "Atlantic/Reykjavik" },
  { title: "GMT+1 Berlin", subtitle: "Europe/Berlin" },
  { title: "GMT+1 Paris", subtitle: "Europe/Paris" },
  { title: "GMT+1 Madrid", subtitle: "Europe/Madrid" },
  { title: "GMT+1 Lagos", subtitle: "Africa/Lagos" },
  { title: "GMT+2 Athens", subtitle: "Europe/Athens" },
  { title: "GMT+2 Cairo", subtitle: "Africa/Cairo" },
  { title: "GMT+2 Johannesburg", subtitle: "Africa/Johannesburg" },
  { title: "GMT+3 Moscow", subtitle: "Europe/Moscow" },
  { title: "GMT+3 Istanbul", subtitle: "Europe/Istanbul" },
  { title: "GMT+3 Nairobi", subtitle: "Africa/Nairobi" },
  { title: "GMT+3:30 Tehran", subtitle: "Asia/Tehran" },
  { title: "GMT+4 Dubai", subtitle: "Asia/Dubai" },
  { title: "GMT+4:30 Kabul", subtitle: "Asia/Kabul" },
  { title: "GMT+5 Karachi", subtitle: "Asia/Karachi" },
  { title: "GMT+5:30 Mumbai", subtitle: "Asia/Kolkata" },
  { title: "GMT+5:45 Kathmandu", subtitle: "Asia/Kathmandu" },
  { title: "GMT+6 Dhaka", subtitle: "Asia/Dhaka" },
  { title: "GMT+7 Bangkok", subtitle: "Asia/Bangkok" },
  { title: "GMT+7 Jakarta", subtitle: "Asia/Jakarta" },
  { title: "GMT+8 Singapore", subtitle: "Asia/Singapore" },
  { title: "GMT+8 Shanghai", subtitle: "Asia/Shanghai" },
  { title: "GMT+8 Hong Kong", subtitle: "Asia/Hong_Kong" },
  { title: "GMT+8 Perth", subtitle: "Australia/Perth" },
  { title: "GMT+9 Tokyo", subtitle: "Asia/Tokyo" },
  { title: "GMT+9 Seoul", subtitle: "Asia/Seoul" },
  { title: "GMT+9:30 Adelaide", subtitle: "Australia/Adelaide" },
  { title: "GMT+10 Sydney", subtitle: "Australia/Sydney" },
  { title: "GMT+12 Auckland", subtitle: "Pacific/Auckland" },
];

// Every IANA zone (from Intl), formatted as "GMT±N City" and sorted by offset.
function buildTimezones(): Suggestion[] {
  let zones: string[] = [];
  try {
    const f = (
      Intl as unknown as { supportedValuesOf?: (k: string) => string[] }
    ).supportedValuesOf;
    if (f) zones = f("timeZone");
  } catch {
    // fall through to the curated list
  }
  if (!zones.length) return TIMEZONES_FALLBACK;
  const now = new Date();
  const rows = zones.map((iana) => {
    let gmt = "";
    try {
      const parts = new Intl.DateTimeFormat("en-US", {
        timeZone: iana,
        timeZoneName: "shortOffset",
      }).formatToParts(now);
      gmt = parts.find((p) => p.type === "timeZoneName")?.value ?? "";
    } catch {
      // leave gmt empty → treated as GMT+0
    }
    const mins = offsetMinutes(gmt);
    const city = iana.split("/").slice(-1)[0].replace(/_/g, " ");
    return { title: `${gmtLabel(mins)} ${city}`, subtitle: iana, mins };
  });
  rows.sort((a, b) => a.mins - b.mins || a.title.localeCompare(b.title));
  return rows.map(({ title, subtitle }) => ({ title, subtitle }));
}

export const TIMEZONES: Suggestion[] = buildTimezones();

export const LOCATIONS: Suggestion[] = [
  {
    title: "100 Main St",
    subtitle: "100 Main St, Springfield",
    recent: true,
  },
  {
    title: "Parking Lot B",
    subtitle: "Parking Lot B, 200 Center St, Springfield",
    recent: true,
  },
  {
    title: "5 Market Square",
    subtitle: "5 Market Square, Riverside, 02138",
    recent: true,
  },
  {
    title: "42 Oak Ave",
    subtitle: "42 Oak Ave, Lakeside, 01880",
    recent: true,
  },
];

// Color of a calendar by name (for the event's left accent bar). Defined after
// ACCOUNTS below via buildCalColor().
let CAL_COLOR: Map<string, Color> | null = null;
export const calColor = (name?: string): Color => {
  if (!CAL_COLOR) {
    CAL_COLOR = new Map();
    for (const acct of ACCOUNTS)
      for (const c of acct.calendars)
        if (!CAL_COLOR.has(c.name)) CAL_COLOR.set(c.name, c.color);
  }
  return (name && CAL_COLOR.get(name)) || DEFAULT_COLOR;
};

// Drop the memoized map so the next calColor() rebuilds from a mutated ACCOUNTS
// (used when a live backend replaces the seed accounts at startup).
export const resetCalColor = () => {
  CAL_COLOR = null;
};

// The color to render an event in: its own override if set, else the calendar's
// color collapsed down to the nearest EVENT-palette color (so an inherited color
// is always a real, selectable event color). Events don't store the calendar
// color, so recoloring a calendar takes effect here at render time — no per-event
// rewrite needed.
export const eventColor = (ev: { color?: Color; calendar?: string }): Color =>
  ev.color ?? toEventColor(calColor(ev.calendar));

// A representative color for an account, used to tag its contacts in the people
// search list: the account's primary/first calendar color (which is usually that
// account's own calendar). Falls back to the default.
export const accountColor = (email: string): Color => {
  const acct = ACCOUNTS.find((a) => a.account === email);
  const own =
    acct?.calendars.find((c) => c.name === email) ?? acct?.calendars[0];
  return own?.color ?? DEFAULT_COLOR;
};

// Sidebar calendar list, grouped by account.
export interface CalAccount {
  account: string;
  photo?: string; // local cached path to the profile picture
  calendars: {
    name: string;
    color: Color;
    rss?: boolean;
    hidden?: boolean;
    // Owner/writer access — only these can be a default / get a star (you can't
    // create events on a read-only calendar). Undefined in the dummy seeds.
    writable?: boolean;
    // Google calendar id, needed to PATCH its color. Undefined in dummy seeds.
    id?: string;
    // The calendar's default popup reminders (minutes before), used by events
    // that don't override them. From Google's calendarList.defaultReminders.
    defaultReminders?: number[];
  }[];
}

// The calendar's default popup-reminder minutes (used when an event defers to
// them), or [] for the dummy seeds / an unknown calendar.
export function calendarDefaultReminders(calName?: string): number[] {
  if (!calName) return [];
  for (const a of ACCOUNTS)
    for (const c of a.calendars)
      if (c.name === calName) return c.defaultReminders ?? [];
  return [];
}

// The effective popup-reminder minutes for an event: its explicit overrides, or
// the owning calendar's defaults.
export function eventReminders(ev: {
  calendar?: string;
  reminders?: number[];
  useDefaultReminders?: boolean;
}): number[] {
  return ev.useDefaultReminders === false
    ? (ev.reminders ?? [])
    : calendarDefaultReminders(ev.calendar);
}

export const ACCOUNTS: CalAccount[] = [
  {
    account: "you@example.com",
    calendars: [
      { name: "you@example.com", color: "basil", writable: true },
      { name: "Tennis Club", color: "cobalt", writable: true },
      {
        name: "Tennis Club Admin",
        color: "grape",
        hidden: true,
        writable: true,
      },
      { name: "Holidays", color: "graphite", rss: true },
    ],
  },
  {
    account: "you@work.example",
    calendars: [
      { name: "you@work.example", color: "cobalt", writable: true },
      { name: "Payroll", color: "graphite", rss: true },
      { name: "Acme Co", color: "tomato", rss: true },
      { name: "Globex", color: "basil", rss: true },
      { name: "Initech", color: "grape", rss: true },
    ],
  },
  {
    account: "you@example.com",
    calendars: [
      { name: "Home", color: "cobalt", writable: true },
      { name: "Work", color: "grape", writable: true },
      { name: "Birthdays", color: "tomato", rss: true },
    ],
  },
];
