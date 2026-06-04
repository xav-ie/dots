import { Astal, Gtk } from "ags/gtk4";
import type Gdk from "gi://Gdk?version=4.0";
import Power from "./modules/Power";
import Workspaces from "./modules/Workspaces";
import Pomodoro from "./modules/Pomodoro";
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
          <Pomodoro />
        </box>
        <box $type="center" />
        <box
          $type="end"
          class="bar-section bar-right"
          spacing={2}
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
