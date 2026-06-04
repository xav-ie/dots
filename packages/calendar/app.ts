import app from "ags/gtk4/app";
import style from "./style.scss";
import Calendar from "./Calendar";
import Gtk from "gi://Gtk?version=4.0";
import { setupTray } from "./tray";
import { setQuitConfirmOpen } from "./state";
import { accent, applyAccent, syncDesktopIcon } from "./theme";
import { accentIcon } from "./palette";

// Held across the single-instance boundary so a second launch (the app launcher,
// while we're hidden in the tray) can re-present the existing window.
let win: Gtk.Window | null = null;
const present = () => win?.present();

app.start({
  instanceName: "calendar",
  css: style,
  gtkTheme: "Adwaita",
  // A second `calendar` invocation hits the running instance here instead of
  // starting a new one — just raise the window (it may be hidden in the tray).
  requestHandler(_argv, res) {
    present();
    res("ok");
  },
  main() {
    // Override @accent with the user's saved pick (no-op at the default) before
    // the window shows, so there's no coral flash on a non-default accent.
    applyAccent();
    // Reconcile the launcher/taskbar icon override with the saved accent (e.g.
    // after a rebuild that changed the icon set).
    syncDesktopIcon();
    win = Calendar() as Gtk.Window;
    app.add_window(win);
    win.present();
    // Real tray icon (StatusNotifierItem). The window hides to tray on close;
    // the tray menu reopens it or starts the (confirmed) quit. Guarded so a tray
    // failure can never take the window down with it.
    try {
      const tray = setupTray({
        onOpen: present,
        onQuit: () => {
          present(); // the confirm lives in the window, so show it first
          setQuitConfirmOpen(true);
        },
        iconName: accentIcon(accent.get()),
      });
      // Keep the tray icon on the accent's pre-generated variant as it changes.
      accent.subscribe(() => tray.setIcon(accentIcon(accent.get())));
    } catch (e) {
      console.error(`[calendar-tray] setup failed: ${e}`);
    }
  },
});
