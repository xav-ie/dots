import app from "ags/gtk4/app";
import style from "./style.scss";
import Spotlight from "./Spotlight";
import { requestMode } from "./controller";
import Gtk from "gi://Gtk?version=4.0";

// Resident, single-instance launcher hosting the app/clipboard/emoji/bluetooth/
// power modes (Spotlight-style). Each keybind re-runs this binary with a mode
// argument; the running instance's requestHandler forwards it here so repeat
// opens just switch the visible mode — no relaunch. Pre-warmed with `--daemon`.
const MODES = ["app", "clipboard", "emoji", "bluetooth", "power"];

function parseMode(argv: string[]): string {
  return argv.find((a) => MODES.includes(a)) ?? "app";
}

app.start({
  instanceName: "spotlight",
  css: style,
  gtkTheme: "Adwaita",
  requestHandler(argv, res) {
    requestMode(parseMode(argv));
    res("ok");
  },
  main(...argv: string[]) {
    const win = Spotlight() as Gtk.Window;
    app.add_window(win);
    // --daemon pre-warms the instance at login without showing it; a plain
    // launch sets the requested mode and presents the window.
    if (!argv.includes("--daemon")) requestMode(parseMode(argv));
  },
});
