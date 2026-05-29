import {
  createBinding,
  createComputed,
  createState,
  For,
  onCleanup,
} from "ags";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import AstalBluetooth from "gi://AstalBluetooth";
import Graphene from "gi://Graphene";
import GLib from "gi://GLib";
import { bump, load, score } from "./frecency";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

function close() {
  app.quit();
}

type ConnState = "off" | "connecting" | "on";

function DeviceRow({
  device,
  onConnect,
  setButton,
  onFocus,
}: {
  device: AstalBluetooth.Device;
  onConnect: () => void;
  setButton: (button: Gtk.Button | null) => void;
  onFocus: (address: string) => void;
}) {
  const name = createBinding(device, "alias");
  const icon = createBinding(device, "icon");

  // Optimistic, single-valued UI state. It is set immediately on click so
  // disconnects feel instant, then reconciled from the device's own notify
  // signals. Being single-valued guarantees the spinner and checkmark are
  // never shown at the same time.
  const [state, setState] = createState<ConnState>(
    device.connected ? "on" : "off",
  );

  const onConnected = device.connect("notify::connected", () => {
    if (device.connected) setState("on");
    else if (!device.connecting) setState("off");
  });
  const onConnecting = device.connect("notify::connecting", () => {
    if (device.connecting) setState("connecting");
    else if (!device.connected) setState("off");
  });
  onCleanup(() => {
    device.disconnect(onConnected);
    device.disconnect(onConnecting);
    setButton(null);
  });

  function onClicked() {
    if (state.get() === "on") {
      setState("off"); // optimistic disconnect
      device.disconnect_device((_, res) => {
        try {
          device.disconnect_device_finish(res);
        } catch (err) {
          console.error("bluetooth-picker: disconnect failed", err);
          setState(device.connected ? "on" : "off"); // resync on failure
        }
      });
    } else {
      setState("connecting"); // optimistic connect
      device.connect_device((_, res) => {
        try {
          device.connect_device_finish(res);
        } catch (err) {
          console.error("bluetooth-picker: connect failed", err);
          setState(device.connected ? "on" : "off"); // resync on failure
        }
      });
      onConnect(); // persist frecency after kicking off the async connect
    }
  }

  return (
    <button
      class="row"
      onClicked={onClicked}
      $={(ref) => setButton(ref as Gtk.Button)}
    >
      <Gtk.EventControllerFocus onEnter={() => onFocus(device.address)} />
      <box spacing={12}>
        <image
          iconName={icon((i) => i || "bluetooth-symbolic")}
          pixelSize={28}
        />
        <label
          label={name((n) => n || device.address)}
          halign={Gtk.Align.START}
          maxWidthChars={32}
          ellipsize={3 /* PANGO_ELLIPSIZE_END */}
        />
        <box hexpand halign={Gtk.Align.END}>
          <Gtk.Spinner spinning visible={state((s) => s === "connecting")} />
          <image
            iconName="object-select-symbolic"
            visible={state((s) => s === "on")}
          />
        </box>
      </box>
    </button>
  );
}

export default function BluetoothPicker() {
  let contentbox: Gtk.Box;
  let win: Astal.Window;
  let powerSwitch: Gtk.Switch;

  const bt = AstalBluetooth.get_default();
  const powered = createBinding(bt, "isPowered");
  const devices = createBinding(bt, "devices");

  // Frecency is snapshotted once at launch and never updated reactively: the
  // list must NOT reshuffle while open (a live re-sort on connect steals focus
  // from the row you just clicked). bump() still persists for the next launch.
  const frecency = load();

  // Row buttons by device address, so launch can focus a connected device.
  const rowButtons = new Map<string, Gtk.Button>();

  // The device whose row currently holds focus. <For> tears down and re-appends
  // every row on each devices() emit (e.g. when a scan finds a device), which
  // drops focus; we restore it to the same device once the rebuild settles.
  let focusedAddress: string | null = null;
  const unsubscribe = devices.subscribe(() => {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      if (focusedAddress) rowButtons.get(focusedAddress)?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  });
  onCleanup(unsubscribe);

  // Connected first, then by frecency, then alphabetically. Only re-sorts when
  // the device set itself changes (e.g. a scan finds a new device).
  const sorted = createComputed(() => {
    return [...devices()].sort((a, b) => {
      if (a.connected !== b.connected) return a.connected ? -1 : 1;
      const diff = score(frecency, b.address) - score(frecency, a.address);
      if (diff !== 0) return diff;
      // alias and name are both nullable for a freshly-discovered device.
      const an = a.alias || a.name || a.address;
      const bn = b.alias || b.name || b.address;
      return an.localeCompare(bn);
    });
  });

  function onConnect(address: string) {
    bump(address); // persisted for next launch; intentionally no live re-sort
  }

  function toggleScan() {
    const adapter = bt.adapter;
    if (!adapter) return;
    if (adapter.discovering) adapter.stop_discovery();
    else adapter.start_discovery();
  }

  // Escape closes; Ctrl+R refreshes (rescans).
  function onKey(
    _e: Gtk.EventControllerKey,
    keyval: number,
    _: number,
    mod: number,
  ) {
    if (keyval === Gdk.KEY_Escape) {
      close();
    } else if (
      keyval === Gdk.KEY_r &&
      (mod & Gdk.ModifierType.CONTROL_MASK) !== 0
    ) {
      toggleScan();
    }
  }

  // Close on click outside the panel.
  function onClick(_e: Gtk.GestureClick, _: number, x: number, y: number) {
    const [, rect] = contentbox.compute_bounds(win);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      close();
      return true;
    }
  }

  return (
    <window
      $={(ref) => (win = ref)}
      name="bluetooth-picker"
      namespace="bluetooth-picker"
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (!visible) return;
        // Focus the top connected device if there is one, else the power switch.
        const connected = sorted().find((d) => d.connected);
        const btn = connected ? rowButtons.get(connected.address) : undefined;
        if (btn) btn.grab_focus();
        else powerSwitch.grab_focus();
      }}
    >
      <Gtk.EventControllerKey onKeyPressed={onKey} />
      <Gtk.GestureClick onPressed={onClick} />
      <box
        $={(ref) => (contentbox = ref)}
        class="panel"
        valign={Gtk.Align.CENTER}
        halign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={12}
      >
        <box class="header" spacing={12}>
          <label class="title" label="Bluetooth" halign={Gtk.Align.START} />
          <button
            class="scan"
            hexpand
            halign={Gtk.Align.END}
            sensitive={powered((p) => p)}
            onClicked={toggleScan}
          >
            <image iconName="view-refresh-symbolic" />
          </button>
          <Gtk.Switch
            $={(ref) => (powerSwitch = ref)}
            active={powered((p) => p)}
            onNotifyActive={({ active }) => {
              if (active !== bt.isPowered) bt.toggle();
            }}
          />
        </box>
        <Gtk.Separator />
        <Gtk.ScrolledWindow
          maxContentHeight={400}
          propagateNaturalHeight
          hscrollbarPolicy={Gtk.PolicyType.NEVER}
        >
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <label
              class="dim"
              label={powered((p) =>
                p ? "No devices yet — hit scan." : "Bluetooth is off.",
              )}
              visible={sorted((d) => d.length === 0)}
            />
            <For each={sorted}>
              {(device) => (
                <DeviceRow
                  device={device}
                  onConnect={() => onConnect(device.address)}
                  setButton={(btn) => {
                    if (btn) rowButtons.set(device.address, btn);
                    else rowButtons.delete(device.address);
                  }}
                  onFocus={(addr) => {
                    focusedAddress = addr;
                  }}
                />
              )}
            </For>
          </box>
        </Gtk.ScrolledWindow>
      </box>
    </window>
  );
}
