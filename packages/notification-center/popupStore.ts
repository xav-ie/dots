import GLib from "gi://GLib";
import AstalNotifd from "gi://AstalNotifd";
import { createState } from "ags";
import { notifd } from "./notifd";
import { centerOpen } from "./controller";

// Per-urgency popup lifetime (ms): how long a toast stays on screen. Resolution
// itself is disabled (ignoreTimeout in notifd.ts), so these only control the
// popup — the notification lives on in the center until dismissed.
const TIMEOUT = { low: 5000, normal: 10000, critical: 20000 };

// Slide+fade duration. Must match the revealer transitionDuration in Popups.tsx
// and the .toast-fade transition in style.scss.
export const ANIM_MS = 450;

function lifetime(n: AstalNotifd.Notification): number {
  const { LOW, CRITICAL } = AstalNotifd.Urgency;
  if (n.urgency === LOW) return TIMEOUT.low;
  if (n.urgency === CRITICAL) return TIMEOUT.critical;
  return TIMEOUT.normal;
}

const [popups, setPopups] = createState(new Array<AstalNotifd.Notification>());
export { popups };

const hideTimers = new Map<number, number>(); // auto-hide → starts the leave
const removeTimers = new Map<number, number>(); // leave anim → actual removal
const leaveCbs = new Map<number, () => void>(); // each toast's animate-out hook

// Each Toast registers a callback so dismissPopup can play its leave animation
// before the row is removed from the list.
export function registerToast(id: number, leave: () => void): void {
  leaveCbs.set(id, leave);
}
export function unregisterToast(id: number): void {
  leaveCbs.delete(id);
}

function clearTimer(map: Map<number, number>, id: number): void {
  const t = map.get(id);
  if (t) {
    GLib.source_remove(t);
    map.delete(id);
  }
}

function remove(id: number): void {
  clearTimer(hideTimers, id);
  clearTimer(removeTimers, id);
  setPopups((ns) => ns.filter((n) => n.id !== id));
}

// Play the toast's leave animation (slide up + fade out), then drop it.
export function dismissPopup(id: number): void {
  clearTimer(hideTimers, id);
  if (removeTimers.has(id)) return; // already leaving
  const leave = leaveCbs.get(id);
  if (!leave) {
    remove(id);
    return;
  }
  leave();
  removeTimers.set(
    id,
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, ANIM_MS, () => {
      remove(id);
      return GLib.SOURCE_REMOVE;
    }),
  );
}

// Opening the center clears the toasts at once (attention moves to the panel).
export function clearPopups(): void {
  for (const id of [...hideTimers.keys()]) clearTimer(hideTimers, id);
  for (const id of [...removeTimers.keys()]) clearTimer(removeTimers, id);
  setPopups([]);
}

notifd.connect("notified", (_, id) => {
  // While the center is open, a new notification goes straight into its list
  // (notifd.ts) — don't also raise a toast. DND suppresses toasts too.
  if (notifd.dontDisturb || centerOpen.get()) return;
  const n = notifd.get_notification(id);
  if (!n) return;
  setPopups((ns) => [n, ...ns.filter((x) => x.id !== id)]);
  clearTimer(hideTimers, id);
  hideTimers.set(
    id,
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, lifetime(n), () => {
      dismissPopup(id);
      return GLib.SOURCE_REMOVE;
    }),
  );
});

notifd.connect("resolved", (_, id) => dismissPopup(id));

centerOpen.subscribe(() => {
  if (centerOpen.get()) clearPopups();
});
