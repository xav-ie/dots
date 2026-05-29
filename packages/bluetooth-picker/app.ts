import app from "ags/gtk4/app";
import style from "./style.scss";
import BluetoothPicker from "./BluetoothPicker";
import Gtk from "gi://Gtk?version=4.0";

// One-shot picker: present the window on launch and let it quit on Escape or
// click-away (see BluetoothPicker). Bound to a key in hyprland.
app.start({
  instanceName: "bluetooth-picker",
  css: style,
  gtkTheme: "Adwaita",
  main() {
    const win = BluetoothPicker() as Gtk.Window;
    app.add_window(win);
    win.present();
  },
});
