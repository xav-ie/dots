import { Gtk } from "ags/gtk4";
import { execAsync } from "ags/process";

// Opens spotlight's power mode — the same as $mainMod+Escape.
export default function Power() {
  return (
    <box class="module power">
      <button
        tooltipText="Power menu"
        onClicked={() =>
          execAsync(["spotlight", "power"]).catch((err) =>
            console.error("bar: spotlight power failed", err),
          )
        }
      >
        <image iconName="system-shutdown-symbolic" pixelSize={16} />
      </button>
    </box>
  ) as Gtk.Widget;
}
