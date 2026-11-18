import AstalNotifd from "gi://AstalNotifd";
import GLib from "gi://GLib";
import { createState } from "ags";

// The first AstalNotifd.get_default() in a process becomes the freedesktop
// notification daemon (it owns org.freedesktop.Notifications). This module is
// imported by the resident `notification-center` app, so that process IS the
// daemon; everything else (the bar's `notifctl -swb`, etc.) connects as a proxy.
export const notifd = AstalNotifd.get_default();

// Keep notifications in the list until the user dismisses one or hits Clear All
// — don't auto-resolve on the sender's expire_timeout. Popups still fade on
// their own per-urgency timer (see popupStore.ts); this only governs the center's
// persistence, matching swaync's "popup fades but stays in the control center".
notifd.ignoreTimeout = true;

// Live list of unresolved notifications, newest first, for the center list.
const [notifications, setNotifications] = createState(
  notifd.get_notifications(),
);
export { notifications };

notifd.connect("notified", (_, id) => {
  const n = notifd.get_notification(id);
  if (!n) return;
  // Drop any prior entry with this id (a replacement) and prepend the new one.
  setNotifications((ns) => [n, ...ns.filter((x) => x.id !== id)]);
});

notifd.connect("resolved", (_, id) => {
  setNotifications((ns) => ns.filter((n) => n.id !== id));
});

export function clearAll(): void {
  for (const n of notifd.get_notifications()) n.dismiss();
}

// `notify` (packages/notify) hints, set as string hints on notify-send.
function stringHint(n: AstalNotifd.Notification, name: string): string | null {
  const v = n.get_hint(name);
  return v ? String(v.unpack()) : null;
}

// x-dots-on-click: JSON argv run when the notification body is clicked or
// activated. Returns whether the notification had one.
export function runOnClick(n: AstalNotifd.Notification): boolean {
  const raw = stringHint(n, "x-dots-on-click");
  if (!raw) return false;
  try {
    const argv = JSON.parse(raw) as string[];
    GLib.spawn_async(null, argv, null, GLib.SpawnFlags.SEARCH_PATH, null);
  } catch (e) {
    console.error(`x-dots-on-click ${raw}: ${e}`);
  }
  n.dismiss();
  return true;
}

// x-dots-expire-at: unix seconds after which the notification leaves the
// center. Swept on a timer since nothing else happens while I'm away.
function sweepExpired(): boolean {
  const now = Date.now() / 1000;
  for (const n of notifd.get_notifications()) {
    const at = Number(stringHint(n, "x-dots-expire-at"));
    if (at && at <= now) n.dismiss();
  }
  return GLib.SOURCE_CONTINUE;
}
sweepExpired();
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 600, sweepExpired);
