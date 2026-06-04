import { exit, programArgs } from "system";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import AstalNotifd from "gi://AstalNotifd";

// swaync-client-compatible CLI for the AGS notification center. The resident
// `notification-center` app owns the bus name, so this short-lived process is a
// proxy: it sees the same notification list / DND state and writes DND through
// the shared GSettings the daemon watches. Flag surface mirrors the swaync-client
// invocations the rest of the config relies on (bar, hypridle, screencast-dnd).

const argv = programArgs;
const has = (...flags: string[]) => flags.some((f) => argv.includes(f));

const notifd = AstalNotifd.get_default();

// Waybar-style status line. The bar only reads `alt`; the scheme is
// `[dnd-]none` / `[dnd-]notification`, matching what swaync emitted.
function statusLine(): string {
  const dnd = notifd.dontDisturb;
  const count = notifd.get_notifications().length;
  return JSON.stringify({
    text: count > 0 ? String(count) : "",
    alt: `${dnd ? "dnd-" : ""}${count > 0 ? "notification" : "none"}`,
    tooltip: `${count} notification${count === 1 ? "" : "s"}`,
    class: dnd ? "dnd" : count > 0 ? "notification" : "none",
  });
}

function setDnd(value: boolean): void {
  notifd.dontDisturb = value;
  // Flush the GSettings write to dconf before we exit so the daemon (and the
  // bar's -swb proxy) actually observe the change.
  Gio.Settings.sync();
}

if (has("-swb", "--subscribe-waybar")) {
  const emit = () => print(statusLine());
  emit();
  notifd.connect("notified", emit);
  notifd.connect("resolved", emit);
  notifd.connect("notify::dont-disturb", emit);
  new GLib.MainLoop(null, false).run();
} else if (has("--get-dnd")) {
  print(notifd.dontDisturb ? "true" : "false");
} else if (has("-dn", "--dnd-on")) {
  setDnd(true);
} else if (has("-df", "--dnd-off")) {
  setDnd(false);
} else if (has("-d", "--toggle-dnd")) {
  setDnd(!notifd.dontDisturb);
} else if (has("-t", "--toggle-panel")) {
  // Forward to the running daemon (single-instance argv forwarding hits its
  // requestHandler, which toggles the center window).
  Gio.Subprocess.new(
    ["notification-center", "toggle"],
    Gio.SubprocessFlags.NONE,
  );
}

// -swb never reaches here (it loops forever); every other path is one-shot.
exit(0);
