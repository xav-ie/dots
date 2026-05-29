import app from "ags/gtk4/app";
import style from "./style.scss";
import PowerPicker from "./PowerPicker";
import Gtk from "gi://Gtk?version=4.0";

// One-shot picker: present the window on launch and let it quit on Escape,
// click-away, or after an action fires (see PowerPicker). Bound to a key in
// hyprland, replacing rofi-powermenu.
app.start({
  instanceName: "power-picker",
  css: style,
  gtkTheme: "Adwaita",
  main() {
    const win = PowerPicker() as Gtk.Window;
    app.add_window(win);
    win.present();
  },
});
