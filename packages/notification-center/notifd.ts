import AstalNotifd from "gi://AstalNotifd";
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
