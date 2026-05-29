import { createState } from "ags";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import { execAsync } from "ags/process";
import Graphene from "gi://Graphene";
import GLib from "gi://GLib";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

function close() {
  app.quit();
}

interface PowerAction {
  id: string;
  label: string;
  icon: string; // freedesktop/Adwaita symbolic icon name
  argv: string[];
  // Reversible actions (lock, suspend) fire immediately; destructive ones
  // (logout, reboot, shutdown) flip the panel into a confirm step first.
  confirm: boolean;
}

// Fixed order — a power menu must never reshuffle (frecency would drift
// "shutdown" under the cursor you reach for "lock"). Mirrors rofi-powermenu.
const ACTIONS: PowerAction[] = [
  {
    id: "lock",
    label: "Lock",
    icon: "system-lock-screen-symbolic",
    argv: ["loginctl", "lock-session"],
    confirm: false,
  },
  {
    id: "suspend",
    label: "Suspend",
    icon: "weather-clear-night-symbolic",
    argv: ["systemctl", "suspend"],
    confirm: false,
    keyval: Gdk.KEY_s,
  },
  {
    id: "logout",
    label: "Log Out",
    icon: "system-log-out-symbolic",
    argv: ["hyprctl", "dispatch", "exit"],
    confirm: true,
    keyval: Gdk.KEY_o,
  },
  {
    id: "reboot",
    label: "Reboot",
    icon: "system-reboot-symbolic",
    argv: ["systemctl", "reboot"],
    confirm: true,
    keyval: Gdk.KEY_r,
  },
  {
    id: "shutdown",
    label: "Shutdown",
    icon: "system-shutdown-symbolic",
    argv: ["systemctl", "poweroff"],
    confirm: true,
    keyval: Gdk.KEY_p,
  },
];

export default function PowerPicker() {
  let contentbox: Gtk.Box;
  let win: Astal.Window;
  let confirmButton: Gtk.Button;
  const buttons: Gtk.Button[] = [];
  // The focused tile, tracked from each button's focus controller. has_focus()
  // is unreliable as a "where am I" probe (it reports the internal focus widget,
  // not the button), so we keep our own index for h/l/arrow navigation.
  let focusedIndex = 0;

  // The action awaiting confirmation, or null while showing the action grid.
  const [pending, setPending] = createState<PowerAction | null>(null);

  function focusAction(index: number) {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      buttons[index]?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Fire-and-forget: the action either tears down this session (logout,
  // poweroff, reboot) or layers over it (lock), so quit immediately rather
  // than awaiting — suspend would otherwise block here until the next resume.
  function run(action: PowerAction) {
    execAsync(action.argv).catch((err) =>
      console.error("power-picker: action failed", err),
    );
    close();
  }

  function trigger(action: PowerAction) {
    if (action.confirm) {
      setPending(action);
      GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
        confirmButton.grab_focus();
        return GLib.SOURCE_REMOVE;
      });
    } else {
      run(action);
    }
  }

  function cancel() {
    const action = pending.get();
    setPending(null);
    if (action) focusAction(ACTIONS.indexOf(action));
  }

  // Move focus along the action row, wrapping at the ends.
  function move(delta: number) {
    const next = (focusedIndex + delta + buttons.length) % buttons.length;
    buttons[next]?.grab_focus();
  }

  function onKey(_e: Gtk.EventControllerKey, keyval: number) {
    if (keyval === Gdk.KEY_Escape) {
      if (pending.get()) cancel();
      else close();
      return true;
    }
    // In the confirm step, leave Enter/click to the buttons.
    if (pending.get()) return false;

    // Navigate the action row with the arrows or vim's h/l; Enter activates the
    // focused tile (handled by the button itself).
    if (keyval === Gdk.KEY_Left || keyval === Gdk.KEY_h) {
      move(-1);
      return true;
    }
    if (keyval === Gdk.KEY_Right || keyval === Gdk.KEY_l) {
      move(1);
      return true;
    }
    return false;
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
      name="power-picker"
      namespace="power-picker"
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (!visible) return;
        focusAction(0);
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
        spacing={16}
      >
        {/* Action grid */}
        <box
          class="actions"
          spacing={12}
          homogeneous
          visible={pending((p) => p === null)}
        >
          {ACTIONS.map((action, i) => (
            <button
              class="action"
              tooltipText={action.label}
              onClicked={() => trigger(action)}
              $={(ref) => (buttons[i] = ref as Gtk.Button)}
            >
              <Gtk.EventControllerFocus onEnter={() => (focusedIndex = i)} />
              <box orientation={Gtk.Orientation.VERTICAL} spacing={10}>
                <image iconName={action.icon} pixelSize={48} />
                <label label={action.label} />
              </box>
            </button>
          ))}
        </box>

        {/* Confirm step for destructive actions */}
        <box
          class="confirm"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={16}
          visible={pending((p) => p !== null)}
        >
          <box spacing={14} halign={Gtk.Align.CENTER}>
            <image iconName={pending((p) => p?.icon ?? "")} pixelSize={40} />
            <label
              class="confirm-label"
              label={pending((p) => (p ? `${p.label}?` : ""))}
            />
          </box>
          <box spacing={12} homogeneous>
            <button
              class="confirm-yes"
              $={(ref) => (confirmButton = ref as Gtk.Button)}
              onClicked={() => {
                const action = pending.get();
                if (action) run(action);
              }}
            >
              <label label="Confirm" />
            </button>
            <button class="confirm-no" onClicked={cancel}>
              <label label="Cancel" />
            </button>
          </box>
        </box>
      </box>
    </window>
  );
}
