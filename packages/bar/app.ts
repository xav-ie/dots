import app from "ags/gtk4/app";
import style from "./style.scss";
import Bar, { CenterBar } from "./Bar";

// Resident status bar daemon, started by the `bar` systemd user service (see
// home-manager/linux/bar). One anchored window per monitor; the service
// restarts the process on monitor hotplug.
function present() {
  // Skip the centre bar: its visibility tracks the pomodoro timer, so
  // presenting it would force an empty pill on screen.
  for (const win of app.get_windows())
    if (!win.name?.startsWith("bar-center")) win.present();
}

app.start({
  instanceName: "bar",
  css: style,
  gtkTheme: "Adwaita",
  // A second `bar` invocation (e.g. from the CLI) re-presents the windows
  // rather than erroring on a missing handler.
  requestHandler(_argv, res) {
    present();
    res("ok");
  },
  main() {
    for (const monitor of app.get_monitors()) {
      const win = Bar(monitor);
      app.add_window(win);
      win.present();
      // CenterBar maps itself via its `visible` binding when a timer runs.
      app.add_window(CenterBar(monitor));
    }
  },
});
