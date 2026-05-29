import app from "ags/gtk4/app";
import style from "./style.scss";
import EmojiPicker from "./EmojiPicker";
import Gtk from "gi://Gtk?version=4.0";

// One-shot picker: present the window on launch and let it quit on Escape,
// click-away, or after a pick (see EmojiPicker). Bound to a key in hyprland.
app.start({
  instanceName: "emoji-picker",
  css: style,
  gtkTheme: "Adwaita",
  main() {
    const win = EmojiPicker() as Gtk.Window;
    app.add_window(win);
    win.present();
  },
});
