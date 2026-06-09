import { createComputed, createState } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync, subprocess } from "ags/process";
import GLib from "gi://GLib";

// uair pomodoro timer. `uairctl listen` streams the formatted countdown, one line
// per tick; it only connects once the uair daemon is up, so retry in a loop until
// it does. The bar bundles uair patched with PR#31 (threaded in as the `uair` arg
// from packages.nix — the package set's pkgs has no overlays) so `listen` is
// newline-delimited and flushed per line. Upstream uses a NUL delimiter and never
// flushes to a pipe, so AGS's line reader saw nothing and this stayed empty.
// Module-scoped (like the notification centre's Osd) so the single stream is
// shared across every monitor's CenterBar.
const [text, setText] = createState("");

// uair stops ticking while paused, so the stream goes silent. Treat >2min of
// silence as "paused and forgotten" and autohide; the next tick (resume/start)
// clears it. The timer is rearmed on every line, so a running timer never hides.
const PAUSE_HIDE_MS = 2 * 60 * 1000;
const [pausedHidden, setPausedHidden] = createState(false);
let hideTimer = 0;
subprocess(
  ["sh", "-c", "while ! uairctl listen 2>/dev/null; do sleep 5; done"],
  (line) => {
    setText(line);
    setPausedHidden(false);
    if (hideTimer) GLib.source_remove(hideTimer);
    hideTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PAUSE_HIDE_MS, () => {
      setPausedHidden(true);
      hideTimer = 0;
      return GLib.SOURCE_REMOVE;
    });
  },
  (err) => console.error("bar: uairctl listen", err),
);

// Non-empty only once a session exists (running or paused), and not autohidden
// after a long pause. Drives the CenterBar window's visibility so the whole pill
// unmaps before the first timer is started.
export const pomodoroActive = createComputed(
  () => text().trim() !== "" && !pausedHidden(),
);

// Click toggles pause/resume (and starts a session if none is running).
export default function Pomodoro() {
  return (
    <box class="module pomodoro" visible={pomodoroActive}>
      <button
        tooltipText="Toggle pomodoro"
        onClicked={() =>
          execAsync(["uair-toggle-and-notify"]).catch((err) =>
            console.error("bar: uair-toggle-and-notify", err),
          )
        }
      >
        <label label={text} />
      </button>
    </box>
  ) as Gtk.Widget;
}
