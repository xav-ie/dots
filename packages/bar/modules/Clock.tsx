import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import GLib from "gi://GLib";

// Ticks once a second. Split into weekday / date / time so the `box` spacing
// controls the gap between the three parts.
function parts(): [string, string, string] {
  const d = GLib.DateTime.new_now_local();
  return [
    d.format("%a") ?? "",
    d.format("%m/%d") ?? "",
    d.format("%I:%M") ?? "",
  ];
}

export default function Clock() {
  const [time, setTime] = createState(parts());
  const source = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
    setTime(parts());
    return GLib.SOURCE_CONTINUE;
  });
  onCleanup(() => GLib.source_remove(source));

  return (
    <box class="module clock" spacing={10}>
      <label label={time((t) => t[0])} />
      <label label={time((t) => t[1])} />
      <label label={time((t) => t[2])} />
    </box>
  ) as Gtk.Widget;
}
