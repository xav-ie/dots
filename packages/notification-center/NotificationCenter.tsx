import { Astal, Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Graphene from "gi://Graphene";
import { createBinding, For } from "ags";
import { notifd, notifications, clearAll } from "./notifd";
import { centerOpen, setCenter } from "./controller";
import { modalFocusTrap } from "./focusTrap";
import Notification from "./Notification";
import Mpris from "./Mpris";
import ScreenFilter from "./ScreenFilter";
import Weather from "./Weather";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

// A fullscreen transparent layer surface (the spotlight/picker shape) holding a
// fixed-size card floated top-right. The full-screen backdrop is what makes a
// click anywhere outside the card close the center — and stops the old
// content-sized window from overlapping (and swallowing clicks on) the bar.
// Escape or the bar bell / $mainMod+N toggles it; keymode EXCLUSIVE grabs the
// keyboard so the first notification can be focused on open.
const WIDTH = 920;
const HEIGHT = 930;

export default function NotificationCenter() {
  let win: Astal.Window;
  let panel: Gtk.Box;
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

  // Close when the press lands on the backdrop (outside the card).
  function handleClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(win);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      setCenter(false);
      return true;
    }
  }

  // First focusable notification row (skipping the always-present empty label).
  function firstRow(): Gtk.Widget | null {
    let child = list?.get_first_child() ?? null;
    while (child && !child.get_focusable()) child = child.get_next_sibling();
    return child;
  }
  // Deferred to idle so a freshly shown/added row is realized before the grab.
  // set_focus_visible keeps GTK painting the :focus ring after a programmatic
  // grab (the flag can be false when a notification arrives mid-session).
  function focusFirst() {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      firstRow()?.grab_focus();
      win?.set_focus_visible(true);
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
      $={(ref) => {
        win = ref;
        // Capture-phase Tab/Shift+Tab cycle over the panel's live focusables
        // (wrapping at both ends), landing on the first notification when opened.
        modalFocusTrap(ref, centerOpen, {
          panel: () => panel,
          initial: firstRow,
        });
      }}
      name="notification-center"
      namespace="notification-center"
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      // NORMAL (not IGNORE) so the compositor shrinks the backdrop to exclude
      // the bar's exclusive zone: the bar stays clickable, the backdrop covers
      // everything below it, and the card lands 8px under the bar like the toasts.
      exclusivity={Astal.Exclusivity.NORMAL}
      keymode={Astal.Keymode.EXCLUSIVE}
      visible={centerOpen}
    >
      <Gtk.EventControllerKey onKeyPressed={handleKey} />
      <Gtk.GestureClick onPressed={handleClick} />
      <box
        $={(ref) => (panel = ref)}
        class="center-panel"
        widthRequest={WIDTH}
        heightRequest={HEIGHT}
        halign={Gtk.Align.END}
        valign={Gtk.Align.START}
        marginTop={8}
        marginEnd={8}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={12}
      >
        {/* Weather sizes to its content; the screen filter hexpands to fill the
            rest of the row. */}
        <box class="top-row" spacing={12}>
          <Weather />
          <ScreenFilter />
        </box>
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
            <label label="Clear All" />
          </button>
        </box>
        {/* focusable=false: GtkScrolledWindow makes itself focusable by default,
            which would otherwise add a dead (un-highlightable) stop to the Tab
            cycle right where Shift+Tab lands. Its rows are the real stops. */}
        <Gtk.ScrolledWindow
          focusable={false}
          vexpand
          hscrollbarPolicy={Gtk.PolicyType.NEVER}
        >
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
