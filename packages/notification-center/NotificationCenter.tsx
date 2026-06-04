import { Astal, Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import { createBinding, For } from "ags";
import { notifd, notifications, clearAll } from "./notifd";
import { centerOpen, setCenter } from "./controller";
import Notification from "./Notification";
import Mpris from "./Mpris";
import Weather from "./Weather";

const { TOP, RIGHT } = Astal.WindowAnchor;

// Fixed-size card anchored top-right with the same anchor/exclusivity/margins as
// the toast popups, so it spawns exactly where they do (below the bar). Escape or
// the bar bell / $mainMod+N toggles it; keymode EXCLUSIVE grabs the keyboard so
// the first notification can be focused on open.
const WIDTH = 920;
const HEIGHT = 930;

export default function NotificationCenter() {
  let list: Gtk.Box;

  const dnd = createBinding(notifd, "dontDisturb");
  const isEmpty = notifications((ns) => ns.length === 0);

  function handleKey(_c: Gtk.EventControllerKey, keyval: number): boolean {
    if (keyval === Gdk.KEY_Escape) {
      setCenter(false);
      return true;
    }
    return false;
  }

  // Grab the first focusable row (skipping the always-present empty label) so
  // it's selected and Enter/Backspace act on it. Deferred to idle so a freshly
  // shown/added row is realized before the grab (the pickers hit the same race).
  function focusFirst() {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      let child = list?.get_first_child() ?? null;
      while (child && !child.get_focusable()) child = child.get_next_sibling();
      child?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // A notification arriving while the center is open is prepended to the list
  // (notifd.ts) and suppressed as a toast (popupStore.ts); focus that new top row
  // so it's immediately actionable.
  notifd.connect("notified", () => {
    if (centerOpen.get()) focusFirst();
  });

  return (
    <window
      name="notification-center"
      namespace="notification-center"
      anchor={TOP | RIGHT}
      marginTop={8}
      marginRight={8}
      exclusivity={Astal.Exclusivity.NORMAL}
      keymode={Astal.Keymode.EXCLUSIVE}
      visible={centerOpen}
      onNotifyVisible={({ visible }) => {
        if (visible) focusFirst();
      }}
    >
      <Gtk.EventControllerKey onKeyPressed={handleKey} />
      <box
        class="center-panel"
        widthRequest={WIDTH}
        heightRequest={HEIGHT}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={12}
      >
        <Weather />
        <Mpris />
        <box class="controls-row" spacing={10}>
          <box class="dnd-row" spacing={10}>
            <label label="Do Not Disturb" halign={Gtk.Align.START} />
            <switch
              active={dnd}
              onNotifyActive={({ active }) => {
                if (active !== notifd.dontDisturb) notifd.dontDisturb = active;
              }}
            />
          </box>
          <button
            class="clear-all"
            hexpand
            halign={Gtk.Align.END}
            onClicked={() => clearAll()}
          >
            {/* Tab from the controls bridges into the notification list, which
                the default focus chain skips past the ScrolledWindow. */}
            <Gtk.EventControllerKey
              onKeyPressed={(_c: Gtk.EventControllerKey, keyval: number) => {
                if (keyval === Gdk.KEY_Tab) {
                  focusFirst();
                  return true;
                }
                return false;
              }}
            />
            <label label="Clear All" />
          </button>
        </box>
        <Gtk.ScrolledWindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
          <box
            $={(ref) => (list = ref)}
            class="list"
            orientation={Gtk.Orientation.VERTICAL}
            spacing={8}
          >
            <label class="empty" label="No notifications" visible={isEmpty} />
            <For each={notifications}>
              {(n) => <Notification notification={n} selectable />}
            </For>
          </box>
        </Gtk.ScrolledWindow>
      </box>
    </window>
  );
}
