import app from "ags/gtk4/app";
import style from "./style.scss";
import ClipboardPicker from "./ClipboardPicker";
import Gtk from "gi://Gtk?version=4.0";

// Resident instance: the first launch builds the window and (unless started
// with --daemon) presents it. While that instance lives, every later launch of
// this same binary is forwarded by GApplication as a request — handled below by
// toggling the window — so repeat opens skip the gjs/GTK cold start entirely.
app.start({
  instanceName: "clipboard-picker",
  css: style,
  gtkTheme: "Adwaita",
  requestHandler(_argv, res) {
    const win = app.get_window("clipboard-picker");
    if (win) win.visible = !win.visible;
    res("ok");
  },
  main(...argv: string[]) {
    const win = ClipboardPicker() as Gtk.Window;
    app.add_window(win);
    // --daemon pre-warms the instance at login without flashing the window;
    // a plain launch (the keybind, cold) shows it immediately.
    if (!argv.includes("--daemon")) win.present();
  },
});
