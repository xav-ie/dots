import { Astal, Gtk } from "ags/gtk4";
import type Gdk from "gi://Gdk?version=4.0";
import Power from "./modules/Power";
import Workspaces from "./modules/Workspaces";
import Pomodoro, { pomodoroActive } from "./modules/Pomodoro";
import Tray, { Network } from "./modules/Tray";
import Volume from "./modules/Volume";
import CavaMic from "./modules/CavaMic";
import Dictation from "./modules/Dictation";
import VirtualHeadset from "./modules/VirtualHeadset";
import Bluetooth from "./modules/Bluetooth";
import Notifications from "./modules/Notifications";
import Clock from "./modules/Clock";

const { TOP, LEFT, RIGHT } = Astal.WindowAnchor;

// One top-anchored bar per monitor. EXCLUSIVE reserves layer-shell space so
// tiled windows sit below it; hyprland's floating-window offset math keys off
// programs.ags-bar.barHeight separately.
export default function Bar(gdkmonitor: Gdk.Monitor) {
  return (
    <window
      name={`bar-${gdkmonitor.connector}`}
      namespace="bar"
      gdkmonitor={gdkmonitor}
      anchor={TOP | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
    >
      {/* Two pills with a transparent gap between them: the centerbox itself
          is transparent and spans the full width (for layout + the layer's
          exclusive zone), while each side cluster carries its own background. */}
      <centerbox class="bar">
        <box $type="start" class="bar-section bar-left" spacing={0}>
          <Power />
          <Workspaces />
        </box>
        <box $type="center" />
        <box
          $type="end"
          class="bar-section bar-right"
          spacing={0}
          halign={Gtk.Align.END}
        >
          <Tray />
          <Dictation />
          <Volume />
          <VirtualHeadset />
          <CavaMic />
          <Network />
          <Bluetooth />
          <Notifications />
          <Clock />
        </box>
      </centerbox>
    </window>
  ) as Astal.Window;
}

// A standalone centered bar: its own top-anchored layer-shell window holding only
// the pomodoro timer, floating in the transparent gap between the main Bar's side
// clusters. Mirrors the notification centre's Osd: anchoring only TOP centers it
// horizontally, IGNORE keeps it from being pushed below the main Bar's exclusive
// zone, OVERLAY puts it on the same plane, and marginTop matches `.bar` so the
// pill lines up with the side pills. `visible` tracks the timer, so the whole
// window unmaps when no session runs; NONE keymode keeps it from stealing focus.
export function CenterBar(gdkmonitor: Gdk.Monitor) {
  return (
    <window
      name={`bar-center-${gdkmonitor.connector}`}
      namespace="bar"
      gdkmonitor={gdkmonitor}
      anchor={TOP}
      marginTop={6}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.NONE}
      visible={pomodoroActive}
    >
      <Pomodoro />
    </window>
  ) as Astal.Window;
}
