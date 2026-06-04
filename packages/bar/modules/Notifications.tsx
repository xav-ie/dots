import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync, subprocess } from "ags/process";

// Notification status from the AGS notification center. `notifctl -swb` streams
// a JSON line on every change with an `alt` of none|notification|dnd-none|
// dnd-notification. Left-click toggles the panel, right-click toggles do-not-disturb.
export default function Notifications() {
  const [alt, setAlt] = createState("none");

  const proc = subprocess(
    ["notifctl", "-swb"],
    (line) => {
      try {
        const { alt: a } = JSON.parse(line) as { alt?: string };
        if (a) setAlt(a);
      } catch {
        // ignore any non-JSON line.
      }
    },
    (err) => console.error("bar: notifctl -swb", err),
  );
  onCleanup(() => proc.kill());

  const icon = alt((a) =>
    a.startsWith("dnd")
      ? "notifications-disabled-symbolic"
      : "preferences-system-notifications-symbolic",
  );
  // `alt` ends with "notification" when the daemon is holding unread notifications
  // (both "notification" and "dnd-notification").
  const hasNotifications = alt((a) => a.endsWith("notification"));

  return (
    <box
      class={alt(
        (a) => `module notifications${a.startsWith("dnd") ? " dnd" : ""}`,
      )}
    >
      <button
        tooltipText="Notifications · right-click for do-not-disturb"
        onClicked={() =>
          execAsync(["notifctl", "-t", "-sw"]).catch((err) =>
            console.error("bar: notifctl toggle", err),
          )
        }
      >
        <Gtk.GestureClick
          button={3 /* right */}
          onPressed={() =>
            execAsync(["notifctl", "-d", "-sw"]).catch((err) =>
              console.error("bar: notifctl dnd", err),
            )
          }
        />
        <overlay>
          <image iconName={icon} pixelSize={16} />
          <box
            $type="overlay"
            class="notif-dot"
            halign={Gtk.Align.END}
            valign={Gtk.Align.START}
            visible={hasNotifications}
          />
        </overlay>
      </button>
    </box>
  ) as Gtk.Widget;
}
