import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync, subprocess } from "ags/process";

// uair pomodoro timer. `uairctl listen` streams the formatted countdown; it
// only succeeds once the uair daemon is up, so retry in a loop until it
// connects. Click toggles pause/resume.
export default function Pomodoro() {
  const [text, setText] = createState("");

  const proc = subprocess(
    ["sh", "-c", "while ! uairctl listen 2>/dev/null; do sleep 5; done"],
    (line) => setText(line),
    (err) => console.error("bar: uairctl listen", err),
  );
  onCleanup(() => proc.kill());

  return (
    <box class="module pomodoro" visible={text((t) => t.trim() !== "")}>
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
