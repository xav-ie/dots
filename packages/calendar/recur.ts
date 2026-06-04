// Recurrence model + human labels, shared by the recurrence dropdown and the
// custom "Repeat" dialog. Persisted as JSON in the event's `recur` field; null
// means the event does not repeat.
export interface Recur {
  freq: "day" | "week" | "month" | "year";
  interval: number;
  weekdays?: number[]; // week freq (0 = Sun)
  monthByWeekday?: boolean; // month freq: by Nth weekday instead of day-of-month
  ends?: { type: "never" | "on" | "after"; until?: string; count?: number };
}

const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MON = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

export function parseRecur(s?: string | null): Recur | null {
  if (!s) return null;
  try {
    return JSON.parse(s) as Recur;
  } catch {
    return null;
  }
}

// Which occurrence of its weekday the date is within the month (1st..5th).
export const nthWeekday = (d: Date) => Math.floor((d.getDate() - 1) / 7) + 1;
const ordinal = (n: number) => {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return `${n}${s[(v - 20) % 10] || s[v] || s[0]}`;
};

function endsText(r: Recur, date: Date): string {
  const e = r.ends;
  if (!e || e.type === "never") return "";
  if (e.type === "after") return ` for ${e.count ?? 1} times`;
  if (e.type === "on" && e.until) {
    const [y, m, d] = e.until.split("-").map(Number);
    return ` until ${DOW[new Date(y, m, d).getDay()]} ${MON[m]} ${d}`;
  }
  return "";
}

// Two-part label: bold primary ("Every week") + muted secondary ("on Tue").
export function recurLabel(
  r: Recur | null,
  date: Date,
): { primary: string; secondary: string } {
  if (!r) return { primary: "Does not repeat", secondary: "" };
  const n = r.interval;
  let primary = "";
  let secondary = "";
  switch (r.freq) {
    case "day":
      primary = n === 1 ? "Every day" : `Every ${n} days`;
      break;
    case "week": {
      const wd = r.weekdays ?? [date.getDay()];
      const isWeekdays =
        wd.length === 5 && [1, 2, 3, 4, 5].every((d) => wd.includes(d));
      if (isWeekdays && n === 1) {
        primary = "Every weekday";
        secondary = "Mon–Fri";
      } else {
        primary = n === 1 ? "Every week" : `Every ${n} weeks`;
        secondary = `on ${wd.map((d) => DOW[d]).join(", ")}`;
      }
      break;
    }
    case "month":
      primary = n === 1 ? "Every month" : `Every ${n} months`;
      secondary = r.monthByWeekday
        ? `on the ${ordinal(nthWeekday(date))} ${DOW[date.getDay()]}`
        : `on the ${ordinal(date.getDate())}`;
      break;
    case "year":
      primary = n === 1 ? "Every year" : `Every ${n} years`;
      secondary = `on ${MON[date.getMonth()]} ${date.getDate()}`;
      break;
  }
  return { primary, secondary: secondary + endsText(r, date) };
}

// The standard preset list for a given event date (excludes "Does not repeat"
// and "Custom…", which the dropdown adds itself).
export function recurPresets(date: Date): Recur[] {
  return [
    { freq: "day", interval: 1 },
    { freq: "week", interval: 1, weekdays: [1, 2, 3, 4, 5] },
    { freq: "week", interval: 1, weekdays: [date.getDay()] },
    { freq: "week", interval: 2, weekdays: [date.getDay()] },
    { freq: "month", interval: 1 },
    { freq: "month", interval: 1, monthByWeekday: true },
    { freq: "year", interval: 1 },
  ];
}

// Stable key for comparing two recurrence configs (to mark the active option).
export function recurKey(r: Recur | null): string {
  if (!r) return "none";
  return JSON.stringify({
    f: r.freq,
    i: r.interval,
    w: (r.weekdays ?? []).slice().sort((a, b) => a - b),
    m: !!r.monthByWeekday,
    e: r.ends ?? { type: "never" },
  });
}
