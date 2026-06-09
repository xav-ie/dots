import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync, subprocess } from "ags/process";

// Virtual-headset mute indicator. `virtual-headset-ctl monitor-mute` streams
// JSON whose `class` is "muted"/"unmuted" (driven by Zoom/Meet over HID) and
// whose `tooltip` names the forwarded source. Left-click toggles mute,
// right-click opens the virtual-headset panel (mute + source picker).
export default function VirtualHeadset() {
  const [muted, setMuted] = createState(false);
  const [present, setPresent] = createState(false);
  const [tooltip, setTooltip] = createState("Virtual headset mic");

  const proc = subprocess(
    ["virtual-headset-ctl", "monitor-mute", "muted", "unmuted"],
    (line) => {
      try {
        const { class: cls, tooltip: tip } = JSON.parse(line) as {
          class?: string;
          tooltip?: string;
        };
        if (cls === "muted" || cls === "unmuted") {
          setMuted(cls === "muted");
          setPresent(true);
        }
        // `tooltip` is e.g. "Muted: <source>" / "Unmuted: <source>".
        if (tip) setTooltip(`${tip} · right-click for panel`);
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
        tooltipText={tooltip}
        onClicked={() =>
          execAsync(["virtual-headset-ctl", "toggle-mute"]).catch((err) =>
            console.error("bar: virtual-headset-ctl toggle-mute", err),
          )
        }
      >
        <Gtk.GestureClick
          button={3 /* right */}
          onPressed={() =>
            execAsync(["virtual-headset-panel", "toggle"]).catch((err) =>
              console.error("bar: virtual-headset-panel toggle", err),
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
