import app from "ags/gtk4/app";
import style from "./style.scss";
import Bar from "./Bar";

// Resident status bar daemon, started by the `bar` systemd user service (see
// home-manager/linux/bar). One anchored window per monitor; the service
// restarts the process on monitor hotplug.
function present() {
  for (const win of app.get_windows()) win.present();
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
    }
  },
});
