import { createState } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import { execAsync } from "ags/process";
import GLib from "gi://GLib";
import { ModeProps, PANEL_CONTENT_H } from "./types";

interface PowerAction {
  id: string;
  label: string;
  icon: string; // freedesktop/Adwaita symbolic icon name
  argv: string[];
  // Reversible actions (lock, suspend) fire immediately; destructive ones
  // (logout, reboot, shutdown) flip into a confirm step first.
  confirm: boolean;
}

// Fixed order — a power menu must never reshuffle.
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
  },
  {
    id: "logout",
    label: "Log Out",
    icon: "system-log-out-symbolic",
    argv: ["hyprctl", "dispatch", "exit"],
    confirm: true,
  },
  {
    id: "reboot",
    label: "Reboot",
    icon: "system-reboot-symbolic",
    argv: ["systemctl", "reboot"],
    confirm: true,
  },
  {
    id: "shutdown",
    label: "Shutdown",
    icon: "system-shutdown-symbolic",
    argv: ["systemctl", "poweroff"],
    confirm: true,
  },
];

export default function PowerMode({ register, close }: ModeProps) {
  let confirmButton: Gtk.Button;
  const buttons: Gtk.Button[] = [];
  // The focused tile, tracked from each button's focus controller (has_focus()
  // reports the internal focus widget, not the button).
  let focusedIndex = 0;

  // The action awaiting confirmation, or null while showing the action grid.
  const [pending, setPending] = createState<PowerAction | null>(null);

  function focusAction(index: number) {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      buttons[index]?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Fire-and-forget: the action tears down or layers over this session, so close
  // immediately rather than awaiting (suspend would otherwise block until resume).
  function run(action: PowerAction) {
    execAsync(action.argv).catch((err) =>
      console.error("spotlight/power: action failed", err),
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

  function move(delta: number) {
    const next = (focusedIndex + delta + buttons.length) % buttons.length;
    buttons[next]?.grab_focus();
  }

  function onShow() {
    setPending(null);
    focusAction(0);
  }

  function onKey(keyval: number) {
    if (keyval === Gdk.KEY_Escape) {
      // In the confirm step, Escape backs out to the grid; otherwise let the
      // shell close.
      if (pending.get()) {
        cancel();
        return true;
      }
      return false;
    }
    // In the confirm step, leave Enter/click to the buttons.
    if (pending.get()) return false;

    // Vertical list: Up/Down (or vim j/k) walk the actions.
    if (keyval === Gdk.KEY_Up || keyval === Gdk.KEY_k) {
      move(-1);
      return true;
    }
    if (keyval === Gdk.KEY_Down || keyval === Gdk.KEY_j) {
      move(1);
      return true;
    }
    return false;
  }

  register({ onShow, onKey });

  return (
    <box
      class="mode mode-power"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={16}
    >
      {/* Action list — a vertical column filling the shared panel content height
          (PANEL_CONTENT_H), so power is exactly as tall as every other mode even
          though it has no search entry above the list. */}
      <box
        class="actions"
        orientation={Gtk.Orientation.VERTICAL}
        spacing={8}
        homogeneous
        heightRequest={PANEL_CONTENT_H}
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
            <box
              spacing={16}
              halign={Gtk.Align.START}
              valign={Gtk.Align.CENTER}
            >
              <image iconName={action.icon} pixelSize={30} />
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
  );
}
