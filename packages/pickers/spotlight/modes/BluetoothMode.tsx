import {
  createBinding,
  createComputed,
  createState,
  For,
  onCleanup,
} from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import { execAsync } from "ags/process";
import AstalBluetooth from "gi://AstalBluetooth";
import GLib from "gi://GLib";
import { frecencyStore } from "../../lib/frecency";
import { ModeProps, PANEL_CONTENT_H } from "./types";

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

  // Optimistic, single-valued UI state: set immediately on click so disconnects
  // feel instant, then reconciled from the device's own notify signals.
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
          console.error("spotlight/bluetooth: disconnect failed", err);
          setState(device.connected ? "on" : "off");
        }
      });
    } else {
      setState("connecting"); // optimistic connect
      device.connect_device((_, res) => {
        try {
          device.connect_device_finish(res);
        } catch (err) {
          console.error("spotlight/bluetooth: connect failed", err);
          setState(device.connected ? "on" : "off");
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
          maxWidthChars={36}
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

export default function BluetoothMode({ register }: ModeProps) {
  let powerSwitch: Gtk.Switch;

  const bt = AstalBluetooth.get_default();
  const powered = createBinding(bt, "isPowered");
  const devices = createBinding(bt, "devices");

  // Frecency reloaded on each show (resident instance), but never reactively
  // mid-session: the list must not reshuffle while open (a live re-sort on
  // connect steals focus from the row you just clicked).
  const fr = frecencyStore("bluetooth");
  const [frecency, setFrecency] = createState(fr.load());

  const rowButtons = new Map<string, Gtk.Button>();

  // <For> tears down and re-appends every row on each devices() emit (e.g. a
  // scan finds a device), which drops focus; restore it to the same device.
  let focusedAddress: string | null = null;
  const unsubscribe = devices.subscribe(() => {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      if (focusedAddress) rowButtons.get(focusedAddress)?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  });
  onCleanup(unsubscribe);

  // Connected first, then by frecency, then alphabetically.
  const sorted = createComputed(() => {
    const fre = frecency();
    return [...devices()].sort((a, b) => {
      if (a.connected !== b.connected) return a.connected ? -1 : 1;
      const diff = fr.score(fre, b.address) - fr.score(fre, a.address);
      if (diff !== 0) return diff;
      const an = a.alias || a.name || a.address;
      const bn = b.alias || b.name || b.address;
      return an.localeCompare(bn);
    });
  });

  function onConnect(address: string) {
    fr.bump(address); // persisted for next open; intentionally no live re-sort
  }

  function toggleScan() {
    const adapter = bt.adapter;
    if (!adapter) return;
    if (adapter.discovering) adapter.stop_discovery();
    else adapter.start_discovery();
  }

  function onShow() {
    setFrecency(fr.load());
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      // Focus the top connected device if there is one, else the power switch.
      const connected = sorted().find((d) => d.connected);
      const btn = connected ? rowButtons.get(connected.address) : undefined;
      if (btn) btn.grab_focus();
      else powerSwitch?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Ctrl+R rescans; Escape closes via the shell default.
  function onKey(keyval: number, mod: number) {
    if (keyval === Gdk.KEY_r && (mod & Gdk.ModifierType.CONTROL_MASK) !== 0) {
      toggleScan();
      return true;
    }
    return false;
  }

  register({ onShow, onKey });

  return (
    <box
      class="mode mode-bluetooth"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
      heightRequest={PANEL_CONTENT_H}
    >
      <box class="header" spacing={12}>
        <button
          class="scan"
          sensitive={powered((p) => p)}
          onClicked={toggleScan}
        >
          <box spacing={8}>
            <image iconName="view-refresh-symbolic" />
            <label label="Scan" />
          </box>
        </button>
        <box hexpand />
        <Gtk.Switch
          $={(ref) => (powerSwitch = ref)}
          valign={Gtk.Align.CENTER}
          active={powered((p) => p)}
          onNotifyActive={({ active }) => {
            if (active === bt.isPowered) return;
            if (active) {
              // bluez won't power on a soft-blocked adapter, so clear the
              // rfkill block (no root needed) before powering on.
              execAsync(["rfkill", "unblock", "bluetooth"])
                .catch((err) =>
                  console.error(
                    "spotlight/bluetooth: rfkill unblock failed",
                    err,
                  ),
                )
                .then(() => {
                  if (bt.adapter) bt.adapter.powered = true;
                });
            } else if (bt.adapter) {
              bt.adapter.powered = false;
            }
          }}
        />
      </box>
      <Gtk.Separator />
      <Gtk.ScrolledWindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
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
  );
}
