import { Astal, Gtk } from "ags/gtk4";
import Gdk from "gi://Gdk?version=4.0";
import GLib from "gi://GLib";
import AstalNotifd from "gi://AstalNotifd";
import { For, createState, onCleanup } from "ags";
import {
  popups,
  registerToast,
  unregisterToast,
  dismissPopup,
  ANIM_MS,
} from "./popupStore";
import Notification from "./Notification";

const { TOP, RIGHT } = Astal.WindowAnchor;

// Match the width a notification has in the center: the panel is 920px wide
// (NotificationCenter.tsx WIDTH) with 16px padding each side, so the card spans
// 888px. Pinning the toast stack to the same width keeps toasts from growing to
// their content and reading wider than the same notification in the center.
const WIDTH = 920 - 32;

// Each toast slides down + fades in on arrival and slides up + fades out on
// leave (popupStore plays the leave via the registered `revealed` setter before
// removing the row). The growing/shrinking revealer smoothly pushes the rest of
// the stack. Hyprland's `no_anim` layerrule keeps the surface from adding its own
// resize animation on top.
function Toast({ n }: { n: AstalNotifd.Notification }) {
  const [revealed, setRevealed] = createState(false);
  registerToast(n.id, () => setRevealed(false));
  onCleanup(() => unregisterToast(n.id));
  // Reveal on the next tick so the revealer starts collapsed and animates in.
  GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
    setRevealed(true);
    return GLib.SOURCE_REMOVE;
  });

  return (
    <Gtk.Revealer
      transitionType={Gtk.RevealerTransitionType.SLIDE_DOWN}
      transitionDuration={ANIM_MS}
      revealChild={revealed}
    >
      <box class={revealed((r) => `toast-fade${r ? " shown" : ""}`)}>
        {/* Swipe-to-dismiss is owned by Notification (shared with the center
            rows). `n.dismiss()` closes it everywhere and the resulting `resolved`
            plays this toast's leave; dismissPopup is also called so the toast
            collapses right away even if the daemon round-trip lags. */}
        <Notification
          notification={n}
          onSwipeDismiss={() => {
            n.dismiss();
            dismissPopup(n.id);
          }}
        />
      </box>
    </Gtk.Revealer>
  );
}

// One layer-shell window per monitor, anchored top-right below the bar. All
// monitors share the same `popups` list (popupStore.ts). Created once per monitor
// in app.ts via app.add_window, matching the bar's per-monitor pattern.
export default function Popup(monitor: Gdk.Monitor) {
  return (
    <window
      name="notification-center-popups"
      namespace="notification-center-popups"
      gdkmonitor={monitor}
      visible={popups((ns) => ns.length > 0)}
      anchor={TOP | RIGHT}
      marginTop={8}
      marginRight={8}
    >
      <box
        class="popups"
        widthRequest={WIDTH}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={8}
      >
        <For each={popups}>{(n) => <Toast n={n} />}</For>
      </box>
    </window>
  ) as Gtk.Window;
}
