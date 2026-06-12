import app from "ags/gtk4/app";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import GioUnix from "gi://GioUnix";
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

// gtk4-layer-shell needs a Wayland display. sudo runs us with the caller's
// environment, and that caller is often a shell whose WAYLAND_DISPLAY is stale
// or unset (e.g. a tmux pane predating a re-attach). DISPLAY usually survives,
// so GDK silently opens XWayland instead, gtk4-layer-shell aborts with a wall of
// CRITICALs, the keyboard grab never happens, and the rejected-because-empty
// password follows. Find the live compositor socket ourselves and pin the
// backend before GTK opens any display.
function ensureWaylandEnv(): void {
  const runtimeDir = GLib.getenv("XDG_RUNTIME_DIR");
  if (!runtimeDir) return;
  const live = (name: string | null) =>
    !!name && GLib.file_test(`${runtimeDir}/${name}`, GLib.FileTest.EXISTS);

  let display = GLib.getenv("WAYLAND_DISPLAY");
  if (!live(display)) {
    display = null;
    const dir = Gio.File.new_for_path(runtimeDir);
    const children = dir.enumerate_children(
      "standard::name",
      Gio.FileQueryInfoFlags.NONE,
      null,
    );
    for (
      let info = children.next_file(null);
      info;
      info = children.next_file(null)
    ) {
      const name = info.get_name();
      if (/^wayland-[0-9]+$/.test(name)) {
        display = name;
        break;
      }
    }
    children.close(null);
    if (display) GLib.setenv("WAYLAND_DISPLAY", display, true);
  }
  if (display) GLib.setenv("GDK_BACKEND", "wayland", true);
}

// Hand the secret to sudo. Our stdout is a pipe, so it's block-buffered:
// gjs's print() leaves the password sitting in that buffer and app.quit() can
// tear the process down before it flushes, so sudo intermittently reads an
// empty line and rejects a correct password. Write straight to fd 1 and flush
// before returning so the bytes are on the pipe no matter how fast we exit.
function emitPassword(password: string): void {
  const stdout = new GioUnix.OutputStream({ fd: 1, closeFd: false });
  stdout.write_all(new TextEncoder().encode(`${password}\n`), null);
  stdout.flush(null);
}

ensureWaylandEnv();

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
        emitPassword(password);
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
