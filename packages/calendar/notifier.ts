// Desktop notifications for upcoming events. A lightweight timer scans the synced
// events and fires a Gio.Notification at each event's popup-reminder offsets
// (resolved from the event, or its calendar's defaults). Fires only for reminders
// that became due within a short grace window, so launching the app doesn't flood
// you with every upcoming event. In-memory dedup keyed by event + offset + start
// instant, so a rescheduled event re-notifies and a restart won't double-fire
// recent ones it already showed in the same window.
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import {
  ALL_DAY,
  EVENTS,
  eventReminders,
  type AllDayEvent,
  type CalEvent,
} from "./data";
import { fmtTime } from "./datetime";
import { googleConfigured } from "./gmap";

const TICK_SECONDS = 30;
const GRACE_MS = 5 * 60 * 1000; // fire reminders that came due in the last 5 min
const HORIZON_MS = 2 * 24 * 60 * 60 * 1000; // ignore events further out (cheap tick)

// Dedup keys (`id|minutes|startInstant`) for reminders already fired.
const fired = new Set<string>();

const isAllDay = (ev: CalEvent | AllDayEvent): boolean => {
  const c = ev as CalEvent;
  return c.start == null || c.allDay === true;
};

// The event's local start instant (midnight for all-day), or null without a date.
function startInstant(ev: CalEvent | AllDayEvent): number | null {
  if (!ev.date) return null;
  const [y, m, d] = ev.date;
  if (isAllDay(ev)) return new Date(y, m, d, 0, 0, 0, 0).getTime();
  const h = (ev as CalEvent).start ?? 0;
  return new Date(
    y,
    m,
    d,
    Math.floor(h),
    Math.round((h - Math.floor(h)) * 60),
  ).getTime();
}

const whenLabel = (ev: CalEvent | AllDayEvent): string =>
  isAllDay(ev) ? "All day" : fmtTime((ev as CalEvent).start ?? 0);

function relLabel(minutes: number): string {
  if (minutes <= 0) return "now";
  if (minutes < 60) return `in ${minutes} min`;
  if (minutes < 1440) {
    const h = Math.round(minutes / 60);
    return `in ${h} hour${h === 1 ? "" : "s"}`;
  }
  const d = Math.round(minutes / 1440);
  return `in ${d} day${d === 1 ? "" : "s"}`;
}

function fire(ev: CalEvent | AllDayEvent, minutes: number) {
  const app = Gio.Application.get_default();
  if (!app) return;
  const n = new Gio.Notification();
  n.set_title(ev.title || "Event");
  n.set_body(`${whenLabel(ev)} · ${relLabel(minutes)}`);
  n.set_priority(Gio.NotificationPriority.HIGH);
  app.send_notification(`cal-reminder-${ev.id}-${minutes}`, n);
}

function tick(): boolean {
  if (!googleConfigured()) return GLib.SOURCE_CONTINUE;
  const now = Date.now();
  for (const ev of [...EVENTS, ...ALL_DAY]) {
    if (!ev.id || ev.id.startsWith("local|") || ev.id.startsWith("busy|"))
      continue;
    const s = startInstant(ev);
    if (s == null || s < now - GRACE_MS || s - now > HORIZON_MS) continue;
    for (const m of eventReminders(ev)) {
      const at = s - m * 60000;
      if (at > now || at < now - GRACE_MS) continue; // outside the due window
      const key = `${ev.id}|${m}|${s}`;
      if (fired.has(key)) continue;
      fired.add(key);
      fire(ev, m);
    }
  }
  // Drop dedup keys for events now well in the past so the set stays small.
  for (const key of fired) {
    const s = Number(key.slice(key.lastIndexOf("|") + 1));
    if (Number.isFinite(s) && s < now - HORIZON_MS) fired.delete(key);
  }
  return GLib.SOURCE_CONTINUE;
}

let started = false;
export function startNotifier() {
  if (started) return;
  started = true;
  GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TICK_SECONDS, tick);
}
