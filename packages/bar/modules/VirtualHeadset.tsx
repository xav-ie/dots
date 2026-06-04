import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync, subprocess } from "ags/process";

// Virtual-headset mute indicator. `virtual-headset-ctl monitor-mute` streams
// JSON whose `class` is "muted"/"unmuted" (driven by Zoom/Meet over HID).
// Left-click toggles mute, right-click restarts the service.
export default function VirtualHeadset() {
  const [muted, setMuted] = createState(false);
  const [present, setPresent] = createState(false);

  const proc = subprocess(
    ["virtual-headset-ctl", "monitor-mute", "muted", "unmuted"],
    (line) => {
      try {
        const { class: cls } = JSON.parse(line) as { class?: string };
        if (cls === "muted" || cls === "unmuted") {
          setMuted(cls === "muted");
          setPresent(true);
        }
      } catch {
        // ignore non-JSON status lines
      }
    },
    (err) => console.error("bar: virtual-headset-ctl monitor-mute", err),
  );
  onCleanup(() => proc.kill());

  return (
    <box
      class={muted((m) => `module virtual-headset${m ? " muted" : ""}`)}
      visible={present}
    >
      <button
        tooltipText="Virtual headset mic · right-click to restart service"
        onClicked={() =>
          execAsync(["virtual-headset-ctl", "toggle-mute"]).catch((err) =>
            console.error("bar: virtual-headset-ctl toggle-mute", err),
          )
        }
      >
        <Gtk.GestureClick
          button={3 /* right */}
          onPressed={() =>
            execAsync(["virtual-headset-ctl", "restart-service"]).catch((err) =>
              console.error("bar: virtual-headset-ctl restart-service", err),
            )
          }
        />
        <image
          iconName={muted((m) =>
            m
              ? "microphone-disabled-symbolic"
              : "audio-input-microphone-symbolic",
          )}
          pixelSize={16}
        />
      </button>
    </box>
  ) as Gtk.Widget;
}
