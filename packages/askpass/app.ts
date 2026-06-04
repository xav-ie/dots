import app from "ags/gtk4/app";
import GLib from "gi://GLib";
import style from "./style.scss";
import Askpass from "./Askpass";
import Gtk from "gi://Gtk?version=4.0";

// SUDO_ASKPASS helper rendered with AGS/Astal in place of zenity. sudo runs this
// binary with the prompt as its argument and reads the password off our stdout:
// we print the secret and exit 0 on submit, or exit non-zero (printing nothing)
// on cancel/timeout so sudo aborts the authentication instead of trying an empty
// password. Wired up in nixosConfigurations/modules/sudo-askpass.nix.
const TIMEOUT_SECONDS = 30;

function parsePrompt(argv: string[]): string {
  const text = argv.find((a) => !a.startsWith("--"));
  return text && text.length > 0 ? text : "Authentication Required";
}

app.start({
  // A unique instance per launch. askpass owns the stdout sudo reads from; a
  // fixed applicationId would route a second, concurrent `sudo -A` to the first
  // instance (GApplication remote command-line), so it would never print to its
  // own stdout and that sudo would hang/fail.
  instanceName: `askpass-${GLib.get_monotonic_time()}`,
  css: style,
  gtkTheme: "Adwaita",
  main(...argv: string[]) {
    const win = Askpass({
      prompt: parsePrompt(argv),
      onSubmit: (password) => {
        print(password);
        app.quit(0);
      },
      onCancel: () => app.quit(1),
    }) as Gtk.Window;
    app.add_window(win);
    win.present();

    // Don't leave an orphaned prompt holding the keyboard grab if the user walks
    // away; mirror the 30s guard the zenity helper had.
    GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TIMEOUT_SECONDS, () => {
      app.quit(1);
      return GLib.SOURCE_REMOVE;
    });
  },
});
