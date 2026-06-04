import { Astal } from "ags/gtk4";
import type Gdk from "gi://Gdk?version=4.0";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

// Four thin layer-shell strips form the frame rather than one full-screen
// click-catcher: a full-screen surface would have to null out its input region
// to stay click-through (one mistake = the whole screen swallows clicks), while
// strips only ever sit on the outer 3px edge. OVERLAY keeps the frame above
// everything including fullscreen windows; IGNORE means it reserves no space and
// no keymode means it never grabs the keyboard mid-share.
function Strip(
  gdkmonitor: Gdk.Monitor,
  edge: "top" | "bottom" | "left" | "right",
) {
  const horizontal = edge === "top" || edge === "bottom";
  const anchor = horizontal
    ? (edge === "top" ? TOP : BOTTOM) | LEFT | RIGHT
    : (edge === "left" ? LEFT : RIGHT) | TOP | BOTTOM;

  return (
    <window
      name={`screencast-border-${edge}-${gdkmonitor.connector}`}
      namespace="screencast-border"
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.OVERLAY}
      anchor={anchor}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
    >
      <box class="edge" hexpand={horizontal} vexpand={!horizontal} />
    </window>
  ) as Astal.Window;
}

// All four edge strips for one monitor, returned hidden; app.ts toggles them.
export default function BorderStrips(gdkmonitor: Gdk.Monitor): Astal.Window[] {
  return (["top", "bottom", "left", "right"] as const).map((edge) =>
    Strip(gdkmonitor, edge),
  );
}
