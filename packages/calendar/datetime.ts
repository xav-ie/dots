// Layout geometry + real-date helpers. HOUR_HEIGHT/DAY geometry feed both the
// SCSS hour-line gradient and the event `put()` offsets. All navigation is
// driven by a single anchor Date (see state.ts), so week/day stepping and the
// mini-calendar share one source of truth.
// Taller than the viewport on purpose: ~14h show at once and the grid scrolls
// (opens at 7 AM). Kept in sync with $hour in style.scss.
import GLib from "gi://GLib";
import { createState } from "ags";

// Pixel height of one hour row. Mutable so app zoom can scale the grid in step
// with the CSS (whose $hour gradient is rescaled by the same factor) — keep it a
// plain `let` (live binding) rather than a const so every consumer reads the
// current value. Not rounded: it must equal `64px × zoom` exactly so the
// CSS-drawn hour lines and the JS-positioned events stay aligned.
export const BASE_HOUR_HEIGHT = 64;
export let HOUR_HEIGHT = BASE_HOUR_HEIGHT;
export function setHourScale(z: number) {
  HOUR_HEIGHT = BASE_HOUR_HEIGHT * z;
}
export const HOURS = 24;

export interface Tz {
  label: string;
  utc: number; // absolute UTC offset in hours; display is relative to TZS[0]
}
// Default gutter timezones (index 0 is the primary/default). Hour labels in the
// other columns are drawn relative to the primary's UTC offset.
export const DEFAULT_TZS: Tz[] = [
  { label: "PDT", utc: -7 },
  { label: "EDT", utc: -4 },
];

// Returns the system's IANA timezone id (e.g. "America/New_York").
export const systemIANA = (): string =>
  Intl.DateTimeFormat().resolvedOptions().timeZone;

// Parses a "GMT±H:MM" string (as produced by Intl shortOffset) to signed minutes.
export function offsetMinutes(gmt: string): number {
  const m = gmt.match(/GMT([+-])?(\d{1,2})(?::(\d{2}))?/);
  if (!m) return 0;
  const sign = m[1] === "-" ? -1 : 1;
  return sign * (parseInt(m[2], 10) * 60 + parseInt(m[3] ?? "0", 10));
}

// Formats a signed-minutes UTC offset as "GMT±H" or "GMT±H:MM".
export function gmtLabel(mins: number): string {
  const sign = mins < 0 ? "−" : "+";
  const a = Math.abs(mins);
  const h = Math.floor(a / 60);
  const mm = a % 60;
  return `GMT${sign}${h}${mm ? ":" + String(mm).padStart(2, "0") : ""}`;
}

// Timezone abbreviation (e.g. "AST", "EDT") for an IANA zone at `now`. Falls
// back to a GMT±N code when ICU has no short name.
function tzAbbrev(iana: string, utc: number): string {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: iana,
      timeZoneName: "short",
    }).formatToParts(new Date());
    const tzn = parts.find((p) => p.type === "timeZoneName")?.value;
    if (tzn && !/^(GMT|UTC)/i.test(tzn)) return tzn;
  } catch {
    // no ICU data — fall through to a GMT code
  }
  return `GMT${utc >= 0 ? "+" : "−"}${Math.abs(utc)}`;
}

// Build a Tz from a TIMEZONES suggestion ("GMT−4 Halifax", "America/Halifax"),
// using the zone's abbreviated form (AST) for the gutter label.
export function tzFromZone(title: string, iana: string): Tz {
  const m = title.match(/GMT([+−-])?\s*(\d+)(?::(\d+))?/);
  let utc = 0;
  if (m) {
    utc = parseInt(m[2], 10) + (m[3] ? parseInt(m[3], 10) / 60 : 0);
    if (m[1] === "−" || m[1] === "-") utc = -utc;
  }
  return { label: tzAbbrev(iana, Math.trunc(utc)), utc };
}

// Returns the current local date with time zeroed (recomputed on every call so
// it's never stale across midnight).
export const today = (): Date => {
  const n = new Date();
  return new Date(n.getFullYear(), n.getMonth(), n.getDate());
};

// Frozen at startup — only use for initial reactive state values. Use today()
// anywhere you need the current date at call time.
export const TODAY = today();

// Reactive now-line position, updated every minute. WeekView binds this so the
// red line advances without requiring an app restart.
const _computeNowHour = () => {
  const n = new Date();
  return n.getHours() + n.getMinutes() / 60;
};
export const [nowHour, _setNowHour] = createState(_computeNowHour());
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 60_000, () => {
  _setNowHour(_computeNowHour());
  return GLib.SOURCE_CONTINUE;
});
// Static snapshot for non-reactive consumers (e.g. initial scroll offset).
export const NOW_HOUR = _computeNowHour();

const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
export const MINI_DOW = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

export function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

export function addMonths(d: Date, n: number): Date {
  const r = new Date(d);
  r.setMonth(r.getMonth() + n);
  return r;
}

export function startOfWeek(d: Date): Date {
  return addDays(d, -d.getDay()); // Sunday-based
}

export function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// The 7 dates (Sun–Sat) of the week containing `anchor`.
export function weekDays(anchor: Date): Date[] {
  const s = startOfWeek(anchor);
  return Array.from({ length: 7 }, (_, i) => addDays(s, i));
}

export const fmtDow = (d: Date) => DOW[d.getDay()];
export const fmtMonthYear = (d: Date) =>
  `${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
export const fmtFullDate = (d: Date) =>
  `${DOW[d.getDay()]} ${MONTHS[d.getMonth()].slice(0, 3)} ${d.getDate()}`;

export interface MiniCell {
  date: Date;
  n: number;
  dim: boolean; // belongs to an adjacent month
  today: boolean;
  sel: boolean; // the anchored day
}

// 6×7 mini-month grid for the month containing (and day selected by) `anchor`.
export function monthGrid(anchor: Date): MiniCell[][] {
  const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  const start = startOfWeek(first);
  const now = today();
  return Array.from({ length: 6 }, (_, w) =>
    Array.from({ length: 7 }, (_, i) => {
      const date = addDays(start, w * 7 + i);
      return {
        date,
        n: date.getDate(),
        dim: date.getMonth() !== anchor.getMonth(),
        today: sameDay(date, now),
        sel: sameDay(date, anchor),
      };
    }),
  );
}

// 7 -> "7 AM", 0 -> "12 AM", 13 -> "1 PM". Wraps mod 24 for TZ offsets.
export function fmtHour(h: number): string {
  const t = ((h % 24) + 24) % 24;
  const hour = Math.floor(t);
  const min = Math.round((t - hour) * 60);
  const ampm = hour < 12 ? "AM" : "PM";
  const display = hour % 12 === 0 ? 12 : hour % 12;
  return min
    ? `${display}:${String(min).padStart(2, "0")} ${ampm}`
    : `${display} ${ampm}`;
}

// 13.75 -> "1:45 PM".
export function fmtTime(h: number): string {
  const hour = Math.floor(h) % 24;
  const min = Math.round((h - Math.floor(h)) * 60);
  const ampm = hour < 12 ? "AM" : "PM";
  const display = hour % 12 === 0 ? 12 : hour % 12;
  const mm = min === 0 ? "" : `:${min.toString().padStart(2, "0")}`;
  return `${display}${mm} ${ampm}`;
}
