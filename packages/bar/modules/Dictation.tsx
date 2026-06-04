import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { readFile } from "ags/file";
import { execAsync } from "ags/process";
import GLib from "gi://GLib";

// hyprwhspr-rs voice dictation indicator (the SUPER+G push-to-talk daemon).
// The daemon atomically rewrites ~/.cache/hyprwhspr-rs/status.json on every
// state change with a `class` of inactive|active|processing|error; we poll it
// once a second (the same contract waybar's module uses) and mirror the state.
// Left-click toggles recording, right-click restarts the service.
const STATUS_FILE = `${GLib.get_user_cache_dir()}/hyprwhspr-rs/status.json`;

export default function Dictation() {
  // "" means the daemon has never written a status file (not installed/running),
  // in which case the module stays hidden.
  const [state, setState] = createState("");

  const poll = () => {
    try {
      const { class: cls } = JSON.parse(readFile(STATUS_FILE)) as {
        class?: string;
      };
      setState(cls ?? "");
    } catch {
      // Missing file or mid-rename read: leave the last known state in place.
    }
  };
  poll();
  const source = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
    poll();
    return GLib.SOURCE_CONTINUE;
  });
  onCleanup(() => GLib.source_remove(source));

  return (
    <box
      class={state((s) => `module dictation ${s}`)}
      visible={state((s) => s !== "")}
    >
      <button
        tooltipText="Voice dictation (Super+G) · right-click to restart"
        onClicked={() =>
          execAsync(["hyprwhspr-rs", "record", "toggle"]).catch((err) =>
            console.error("bar: hyprwhspr-rs record toggle", err),
          )
        }
      >
        <Gtk.GestureClick
          button={3 /* right */}
          onPressed={() =>
            execAsync([
              "systemctl",
              "--user",
              "restart",
              "hyprwhspr-rs.service",
            ]).catch((err) => console.error("bar: restart hyprwhspr-rs", err))
          }
        />
        <image
          iconName={state((s) =>
            s === "error"
              ? "dictation-diamond-outline-symbolic"
              : "dictation-diamond-symbolic",
          )}
          pixelSize={16}
        />
      </button>
    </box>
  ) as Gtk.Widget;
}
