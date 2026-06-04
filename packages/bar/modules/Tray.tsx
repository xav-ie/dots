import { createBinding, createComputed, For, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import AstalTray from "gi://AstalTray";
import Gio from "gi://Gio";
import { derived } from "./reactive";

// nm-applet registers its StatusNotifier item under this id. It's pulled out of
// the general tray and rendered at the bar's network slot by Network() below.
const NM_APPLET_ID = "nm-applet";

// nm-applet advertises its own bundled colour raster icons (nm-device-wired,
// nm-signal-75, …). Map those names onto the Adwaita `network-*-symbolic` set
// the rest of the bar uses so the tray item renders the same glyph and inherits
// `.module image` recolouring. Returns null for anything else (keep its gicon).
function nmSymbolic(name: string | null): string | null {
  if (!name || !name.startsWith("nm-")) return null;
  const signal = name.match(/^nm-signal-(\d+)/);
  if (signal) {
    const n = Number(signal[1]);
    if (n >= 88) return "network-wireless-signal-excellent-symbolic";
    if (n >= 63) return "network-wireless-signal-good-symbolic";
    if (n >= 38) return "network-wireless-signal-ok-symbolic";
    if (n >= 13) return "network-wireless-signal-weak-symbolic";
    return "network-wireless-signal-none-symbolic";
  }
  if (name.startsWith("nm-vpn-connecting"))
    return "network-vpn-acquiring-symbolic";
  if (name.startsWith("nm-vpn")) return "network-vpn-symbolic";
  if (name.startsWith("nm-stage")) return "network-wireless-acquiring-symbolic";
  if (name.startsWith("nm-device-wired")) return "network-wired-symbolic";
  if (name.startsWith("nm-device-wireless")) return "network-wireless-symbolic";
  if (
    name.startsWith("nm-tech-") ||
    name.startsWith("nm-mb-") ||
    name.startsWith("nm-wwan")
  )
    return "network-cellular-symbolic";
  if (name === "nm-adhoc") return "network-wireless-hotspot-symbolic";
  if (name === "nm-no-connection") return "network-offline-symbolic";
  return null;
}

// StatusNotifier host: nm-applet, bitwarden, etc. Each item is a MenuButton
// exposing its dbusmenu. This is the session's SNI host, which is why udiskie's
// own tray stays disabled (see home-manager/linux/default.nix).
function TrayItem(item: AstalTray.TrayItem) {
  const gicon = derived([item], () => {
    const symbolic = nmSymbolic(item.iconName);
    return symbolic ? Gio.ThemedIcon.new(symbolic) : item.gicon;
  });

  return (
    <menubutton
      tooltipMarkup={createBinding(item, "tooltipMarkup")}
      menuModel={createBinding(item, "menuModel")}
      $={(self: Gtk.MenuButton) => {
        // Action names in the dbusmenu model are namespaced under "dbusmenu".
        const apply = () =>
          self.insert_action_group("dbusmenu", item.actionGroup);
        apply();
        const id = item.connect("notify::action-group", apply);
        onCleanup(() => item.disconnect(id));
      }}
    >
      <image gicon={gicon} pixelSize={16} />
    </menubutton>
  );
}

export default function Tray() {
  const tray = AstalTray.get_default();
  const items = createBinding(tray, "items");
  // Everything except nm-applet, which Network() renders at the network slot.
  const others = createComputed(() =>
    items().filter((item) => item.id !== NM_APPLET_ID),
  );
  // Collapse the module entirely when there are no tray icons, so its padding
  // doesn't leave a stray gap in the bar.
  const visible = createComputed(() => others().length > 0);

  return (
    <box class="module tray" spacing={1} visible={visible}>
      <For each={others}>{(item: AstalTray.TrayItem) => TrayItem(item)}</For>
    </box>
  ) as Gtk.Widget;
}

// nm-applet's tray item, rendered at the bar's old network-widget slot. Reuses
// the TrayItem renderer (so its icon is remapped to the Adwaita symbolic set),
// filtered down to just the nm-applet item.
export function Network() {
  const tray = AstalTray.get_default();
  const items = createBinding(tray, "items");
  const nmItem = createComputed(() =>
    items().filter((item) => item.id === NM_APPLET_ID),
  );

  return (
    <box class="module network" spacing={1}>
      <For each={nmItem}>{(item: AstalTray.TrayItem) => TrayItem(item)}</For>
    </box>
  ) as Gtk.Widget;
}
