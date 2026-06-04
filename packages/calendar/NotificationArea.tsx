import { For } from "ags";
import { Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import { iconPx } from "./zoom";
import { a11y } from "./a11y";
import {
  clearFocused,
  dismiss,
  notifications,
  setFocused,
  type Note,
} from "./notify";

const START = Gtk.Align.START;

// Top-center error/info notifications. The newest is appended to the bottom and
// its close (×) button grabs focus; auto-dismiss pauses while focused.
export default function NotificationArea() {
  return (
    <box
      class="notif-area"
      halign={Gtk.Align.CENTER}
      valign={START}
      orientation={Gtk.Orientation.VERTICAL}
      spacing={6}
    >
      <For each={notifications}>
        {(n: Note) => {
          const list = notifications.get();
          const newest = list.length > 0 && list[list.length - 1].id === n.id;
          return (
            <box
              class={`notif notif-${n.kind}`}
              spacing={9}
              accessibleRole={Gtk.AccessibleRole.ALERT}
            >
              <image
                iconName={
                  n.kind === "error"
                    ? "dialog-error-symbolic"
                    : "dialog-information-symbolic"
                }
                pixelSize={iconPx(15)}
                valign={Gtk.Align.CENTER}
              />
              <label
                class="notif-msg"
                label={n.message}
                halign={START}
                hexpand
                wrap
                maxWidthChars={46}
              />
              <button
                class="notif-x"
                tooltipText="Dismiss"
                valign={Gtk.Align.CENTER}
                onClicked={() => dismiss(n.id)}
                $={(b: Gtk.Button) => {
                  a11y(b, "Dismiss notification");
                  const f = new Gtk.EventControllerFocus();
                  f.connect("enter", () => setFocused(n.id));
                  f.connect("leave", () => clearFocused(n.id));
                  b.add_controller(f);
                  // Focus the newest notification's ×, retrying until it's mapped
                  // (grab_focus is a no-op before then).
                  if (newest) {
                    let tries = 0;
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 30, () => {
                      if (b.get_mapped()) {
                        b.grab_focus();
                        return GLib.SOURCE_REMOVE;
                      }
                      return ++tries < 20
                        ? GLib.SOURCE_CONTINUE
                        : GLib.SOURCE_REMOVE;
                    });
                  }
                }}
              >
                <image
                  iconName="window-close-symbolic"
                  pixelSize={iconPx(12)}
                />
              </button>
            </box>
          );
        }}
      </For>
    </box>
  );
}
