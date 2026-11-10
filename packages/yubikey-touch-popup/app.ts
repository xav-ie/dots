import app from "ags/gtk4/app";
import Gio from "gi://Gio";
import GLib from "gi://GLib";
import style from "./style.scss";
import Popup, { Mode } from "./Popup";

// Resident popup for YubiKey prompts on this desktop. Two inputs decide what
// shows, "insert" winning over "touch":
//   - the insert flag: sudo's PAM hook (modules/nixos/sudo-yubikey.nix) creates
//     it while it waits for a key that isn't plugged in, and removes it when the
//     key arrives or it gives up.
//   - yubikey-touch-detector's socket, which sends fixed 5-byte events: `GPG_1`
//     when the key starts waiting for a touch, `GPG_0` when it stops (likewise
//     U2F_ and MAC_).
const runtime = GLib.get_user_runtime_dir();
const INSERT_FLAG = `${runtime}/yubikey-insert`;
const DETECTOR_SOCKET = `${runtime}/yubikey-touch-detector.socket`;
const RECONNECT_SECONDS = 2;

let popup: ReturnType<typeof Popup>;
// Held for the app's lifetime; a collected monitor stops reporting changes.
let flagMonitor: Gio.FileMonitor;
let insert = false;
let touch = false;

function render() {
  const mode: Mode | null = insert ? "insert" : touch ? "touch" : null;
  popup.show(mode);
}

function watchInsertFlag() {
  const flag = Gio.File.new_for_path(INSERT_FLAG);
  insert = flag.query_exists(null);
  flagMonitor = flag.monitor_file(Gio.FileMonitorFlags.NONE, null);
  flagMonitor.connect("changed", () => {
    insert = flag.query_exists(null);
    render();
  });
}

function reconnectLater() {
  touch = false;
  render();
  GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, RECONNECT_SECONDS, () => {
    listenToDetector();
    return GLib.SOURCE_REMOVE;
  });
}

// The detector is socket-activated, so connecting also starts it.
function listenToDetector() {
  const client = new Gio.SocketClient();
  const address = new Gio.UnixSocketAddress({ path: DETECTOR_SOCKET });
  client.connect_async(address, null, (_client, result) => {
    let connection: Gio.SocketConnection;
    try {
      connection = client.connect_finish(result);
    } catch {
      reconnectLater();
      return;
    }
    const input = connection.get_input_stream();
    const readEvent = () =>
      input.read_bytes_async(5, GLib.PRIORITY_DEFAULT, null, (_stream, readResult) => {
        let bytes: GLib.Bytes | null = null;
        try {
          bytes = input.read_bytes_finish(readResult);
        } catch {
          bytes = null;
        }
        if (bytes === null || bytes.get_size() === 0) {
          connection.close(null);
          reconnectLater();
          return;
        }
        const event = new TextDecoder().decode(bytes.toArray());
        if (event.endsWith("_1")) touch = true;
        else if (event.endsWith("_0")) touch = false;
        render();
        readEvent();
      });
    readEvent();
  });
}

app.start({
  instanceName: "yubikey-touch-popup",
  css: style,
  gtkTheme: "Adwaita",
  main() {
    popup = Popup();
    app.add_window(popup.win);
    // Resident with no window showing most of the time.
    app.hold();
    watchInsertFlag();
    listenToDetector();
    render();
  },
});
