import app from "ags/gtk4/app";
import { execAsync, subprocess } from "ags/process";
import type { Astal } from "ags/gtk4";
import style from "./style.scss";
import BorderStrips from "./Border";
import StopButton from "./StopButton";

// Resident overlay that frames every monitor in red while a screen-share is
// live, started by the `screencast-border` systemd user service. Detection
// mirrors the existing screencast-dnd service: xdg-desktop-portal-hyprland
// publishes each cast as a PipeWire node with media.class "Video/Source" and
// media.name "xdph-streaming-<rand>" (see xdph src/portals/Screencopy.cpp), so
// we watch pw-mon's event stream for those nodes appearing and disappearing.

// PipeWire node ids of the casts currently streaming. Doubles as the kill list
// for the "Stop sharing" pill.
const active = new Set<number>();

// Every overlay window across all monitors, toggled together.
let windows: Astal.Window[] = [];

function setSharing(on: boolean) {
  for (const win of windows) win.visible = on;
}

// Destroy the streaming PipeWire nodes to stop the cast. The share is really
// owned by the consuming app (browser/Zoom/OBS); tearing down the source node is
// the only handle we have from outside it, and it cuts the feed. pw-mon will
// then report the removals and the border hides itself.
function stopSharing() {
  for (const id of active) {
    execAsync(["pw-cli", "destroy", String(id)]).catch((err) =>
      console.error(`screencast-border: pw-cli destroy ${id}`, err),
    );
  }
}

// Parse pw-mon's block-per-event output. Each event is a run of indented lines
// terminated by a blank separator (--print-separator); we accumulate the fields
// we care about and commit on the blank line, exactly like screencast-dnd.nu.
function watch() {
  let action = "";
  let id = -1;
  let isNode = false;
  let isVideoSource = false;
  let isXdphStream = false;

  const reset = () => {
    action = "";
    id = -1;
    isNode = false;
    isVideoSource = false;
    isXdphStream = false;
  };

  const commit = () => {
    const was = active.size > 0;

    if (
      (action === "added" || action === "changed") &&
      isNode &&
      isVideoSource &&
      isXdphStream &&
      id >= 0
    ) {
      active.add(id);
    } else if (action === "removed" && id >= 0) {
      active.delete(id);
    }

    const now = active.size > 0;
    if (now !== was) setSharing(now);
    reset();
  };

  const proc = subprocess(
    ["pw-mon", "--no-colors", "--hide-params", "--print-separator"],
    (line) => {
      if (line === "") {
        commit();
        return;
      }
      const t = line.trim();
      if (t === "added:") action = "added";
      else if (t === "removed:") action = "removed";
      else if (t === "changed:") action = "changed";
      else if (t.startsWith("id:")) {
        const n = Number.parseInt(t.split(/\s+/)[1] ?? "", 10);
        id = Number.isNaN(n) ? -1 : n;
      } else if (t.startsWith("type:")) {
        isNode = t.includes("PipeWire:Interface:Node");
      } else if (t.startsWith("media.class")) {
        isVideoSource = t.includes('"Video/Source"');
      } else if (t.startsWith("media.name")) {
        isXdphStream = t.includes('"xdph-streaming-');
      }
    },
    (err) => console.error("screencast-border: pw-mon", err),
  );

  return proc;
}

app.start({
  instanceName: "screencast-border",
  css: style,
  gtkTheme: "Adwaita",
  // A second invocation just re-presents (harmless no-op for a hidden overlay).
  requestHandler(_argv, res) {
    res("ok");
  },
  main() {
    for (const monitor of app.get_monitors()) {
      const strips = BorderStrips(monitor);
      const stop = StopButton(monitor, stopSharing);
      for (const win of [...strips, stop]) {
        app.add_window(win);
        windows.push(win);
      }
    }
    watch();
  },
});
