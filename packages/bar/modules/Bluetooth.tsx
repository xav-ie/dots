import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync } from "ags/process";
import AstalBluetooth from "gi://AstalBluetooth";

// Bluetooth power + connected-device summary from AstalBluetooth. Click opens
// spotlight's bluetooth mode.
export default function Bluetooth() {
  const bt = AstalBluetooth.get_default();

  const read = () => {
    if (!bt.isPowered) {
      return {
        icon: "bluetooth-disabled-symbolic",
        cls: "off",
        tooltip: "Bluetooth off",
      };
    }
    const connected = bt.devices.filter((d) => d.connected);
    if (connected.length > 0) {
      return {
        icon: "bluetooth-active-symbolic",
        cls: "connected",
        tooltip: connected
          .map((d) => d.alias || d.name || d.address)
          .join("\n"),
      };
    }
    return {
      icon: "bluetooth-symbolic",
      cls: "",
      tooltip: "No devices connected",
    };
  };

  const [state, setState] = createState(read());
  const refresh = () => setState(read());

  // Track power/device-list changes on the adapter, plus connected-state on
  // each device. Device handlers are rebuilt whenever the device set changes.
  const deviceHandlers = new Map<AstalBluetooth.Device, number>();
  const resubscribe = () => {
    for (const [dev, id] of deviceHandlers) dev.disconnect(id);
    deviceHandlers.clear();
    for (const dev of bt.devices) {
      deviceHandlers.set(dev, dev.connect("notify::connected", refresh));
    }
    refresh();
  };
  const btId = bt.connect("notify", resubscribe);
  resubscribe();
  onCleanup(() => {
    bt.disconnect(btId);
    for (const [dev, id] of deviceHandlers) dev.disconnect(id);
  });

  return (
    <box class={state((s) => `module bluetooth ${s.cls}`)}>
      <button
        tooltipText={state((s) => s.tooltip)}
        onClicked={() =>
          execAsync(["spotlight", "bluetooth"]).catch((err) =>
            console.error("bar: spotlight bluetooth failed", err),
          )
        }
      >
        <image iconName={state((s) => s.icon)} pixelSize={16} />
      </button>
    </box>
  ) as Gtk.Widget;
}
