// Transient notifications (mostly errors surfaced from Google writes/sync),
// shown in a top-center stack. notify() appends to the list and auto-dismisses
// after ~5s — but not while the notification is focused (the user is reading it),
// so only the focused one persists; older/unfocused ones drop off.
import { createState } from "ags";
import GLib from "gi://GLib";

export interface Note {
  id: number;
  message: string;
  kind: "error" | "info";
}

let counter = 0;
// The notification whose close button currently has focus (0 = none).
let focusedId = 0;
export const setFocused = (id: number) => {
  focusedId = id;
};
export const clearFocused = (id: number) => {
  if (focusedId === id) focusedId = 0;
};

export const [notifications, setNotifications] = createState<Note[]>([]);

export function dismiss(id: number) {
  setNotifications((ns) => ns.filter((n) => n.id !== id));
}

export function notify(message: string, kind: Note["kind"] = "error"): number {
  const id = ++counter;
  if (kind === "error") console.error("calendar:", message);
  setNotifications((ns) => [...ns, { id, message, kind }]);
  // Re-check every 5s: keep it while focused, otherwise drop it.
  GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
    if (focusedId === id) return GLib.SOURCE_CONTINUE;
    dismiss(id);
    return GLib.SOURCE_REMOVE;
  });
  return id;
}
