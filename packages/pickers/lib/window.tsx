import { Astal, Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import Graphene from "gi://Graphene";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

// Close a picker: a one-shot caller quits the process; a resident one (the
// spotlight launcher) hides its window instead so the next open is instant.
export function closePicker(name: string, resident = false): void {
  if (resident) {
    const win = app.get_window(name);
    if (win) win.visible = false;
  } else {
    app.quit();
  }
}

interface PickerWindowProps {
  // Layer-shell namespace and GTK window id (matched by `window#<name>` in CSS).
  name: string;
  // Resident pickers hide instead of quitting on close (default false).
  resident?: boolean;
  // Vertical gap between the panel's children (default 16).
  spacing?: number;
  // Run when the window becomes visible (focus a widget, refresh state, …).
  onShow?: () => void;
  // Picker-specific key handling. Return true to consume the key; otherwise the
  // window's default Escape-to-close still applies. `mod` is the modifier mask,
  // `controller` the originating EventControllerKey (for .forward()).
  onKey?: (
    keyval: number,
    mod: number,
    controller: Gtk.EventControllerKey,
  ) => boolean | void;
  // Receives the window ref so the caller can read focus etc.
  setup?: (win: Astal.Window) => void;
  children?: any;
}

// The shared shell every picker mounts inside: a fullscreen-anchored, transparent
// layer surface with EXCLUSIVE keyboard focus, a centered `.panel`, click-away to
// close, and Escape to close. Picker-specific content goes in `children`.
export default function PickerWindow({
  name,
  resident = false,
  spacing = 16,
  onShow,
  onKey,
  setup,
  children,
}: PickerWindowProps) {
  let win: Astal.Window;
  let panel: Gtk.Box;

  const close = () => closePicker(name, resident);

  function handleKey(
    controller: Gtk.EventControllerKey,
    keyval: number,
    _keycode: number,
    mod: number,
  ) {
    if (onKey?.(keyval, mod, controller) === true) return true;
    if (keyval === Gdk.KEY_Escape) {
      close();
      return true;
    }
    return false;
  }

  // Close when the press lands outside the panel.
  function handleClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(win);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      close();
      return true;
    }
  }

  return (
    <window
      $={(ref) => {
        win = ref;
        setup?.(ref);
      }}
      name={name}
      namespace={name}
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (visible) onShow?.();
      }}
    >
      <Gtk.EventControllerKey onKeyPressed={handleKey} />
      <Gtk.GestureClick onPressed={handleClick} />
      <box
        $={(ref) => (panel = ref)}
        class="panel"
        valign={Gtk.Align.CENTER}
        halign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={spacing}
      >
        {children}
      </box>
    </window>
  );
}
