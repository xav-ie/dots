import { Astal, Gtk } from "ags/gtk4";
import type Gdk from "gi://Gdk?version=4.0";

const { TOP } = Astal.WindowAnchor;

// A small "Stop sharing" pill hung from the top edge, centered, inline with the
// frame. Its own layer-shell surface is sized to the pill, so it's the only part
// of the overlay that captures clicks — the rest of the frame stays passive.
export default function StopButton(
  gdkmonitor: Gdk.Monitor,
  onStop: () => void,
) {
  return (
    <window
      name={`screencast-border-stop-${gdkmonitor.connector}`}
      namespace="screencast-border"
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.OVERLAY}
      anchor={TOP}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
    >
      <button
        class="stop"
        tooltipText="Stop sharing your screen"
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.START}
        onClicked={onStop}
      >
        <box spacing={6}>
          <image iconName="media-playback-stop-symbolic" pixelSize={12} />
          <label label="Stop sharing" />
        </box>
      </button>
    </window>
  ) as Astal.Window;
}
