import app from "ags/gtk4/app";
import Gtk from "gi://Gtk?version=4.0";
import style from "./style.scss";
import "./popupStore"; // wires the toast lifecycle onto the daemon (pulls in notifd)
import Popup from "./Popups";
import Osd from "./Osd";
import NotificationCenter from "./NotificationCenter";
import { toggleCenter, setCenter } from "./controller";

// Resident notification daemon, started by the `notification-center` systemd
// user service. Importing ./popups creates AstalNotifd.get_default() in this
// process, making it the freedesktop notification server. It renders the toast
// popups (one window per monitor) and the control center.
app.start({
  instanceName: "notification-center",
  css: style,
  gtkTheme: "Adwaita",
  // `notifctl -t` re-invokes this binary with `toggle`; single-instance forwards
  // it here. (DND is handled in notifctl directly against shared GSettings.)
  requestHandler(argv, res) {
    const cmd = argv[0];
    if (cmd === "toggle") toggleCenter();
    else if (cmd === "open" || cmd === "present") setCenter(true);
    else if (cmd === "close") setCenter(false);
    res("ok");
  },
  main(...argv: string[]) {
    // A control invocation (notifctl -t → `notification-center toggle`) only
    // reaches main() when no daemon is already running — a running daemon would
    // have handled it via requestHandler. Don't bootstrap a rogue daemon outside
    // the systemd service (that squats the single-instance name and blocks the
    // service); just exit. The unit always launches with no args.
    const CONTROL = ["toggle", "open", "close", "present"];
    if (argv.some((a) => CONTROL.includes(a))) {
      app.quit();
      return;
    }
    for (const monitor of app.get_monitors()) app.add_window(Popup(monitor));
    app.add_window(Osd() as Gtk.Window);
    app.add_window(NotificationCenter() as Gtk.Window);
  },
});
