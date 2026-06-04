import { Astal, Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Graphene from "gi://Graphene";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

interface AskpassProps {
  // Text sudo handed us as the prompt (argv[1]); shown above the field.
  prompt: string;
  // Called with the typed secret when the user submits (Enter).
  onSubmit: (password: string) => void;
  // Called on any non-submit dismissal (Escape, click-away).
  onCancel: () => void;
}

// The GUI half of the SUDO_ASKPASS helper: a centered, keyboard-exclusive layer
// surface holding a single masked entry. Enter submits; Escape or a click
// outside the panel cancels (the app-level timeout in app.ts also cancels).
export default function Askpass({ prompt, onSubmit, onCancel }: AskpassProps) {
  let win: Astal.Window;
  let panel: Gtk.Box;
  let entry: Gtk.Entry;

  function handleKey(_c: Gtk.EventControllerKey, keyval: number) {
    if (keyval === Gdk.KEY_Escape) {
      onCancel();
      return true;
    }
    return false;
  }

  // Cancel when the press lands outside the panel.
  function handleClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(win);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      onCancel();
      return true;
    }
  }

  return (
    <window
      $={(ref) => (win = ref)}
      name="askpass"
      namespace="askpass"
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (!visible) return;
        // Defer to idle so the entry is realized before the focus grab — a
        // synchronous grab at present() can miss (see the pickers' showActive).
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
          entry.grab_focus();
          return GLib.SOURCE_REMOVE;
        });
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
        spacing={16}
      >
        <box class="header" orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <image iconName="dialog-password-symbolic" pixelSize={48} />
          <label
            class="title"
            label={prompt}
            wrap
            maxWidthChars={36}
            justify={Gtk.Justification.CENTER}
          />
        </box>
        <entry
          $={(ref) => (entry = ref)}
          class="password"
          visibility={false}
          primaryIconName="dialog-password-symbolic"
          placeholderText="Password"
          inputPurpose={Gtk.InputPurpose.PASSWORD}
          onActivate={() => onSubmit(entry.text)}
        />
        <label class="hint dim" label="Enter to confirm · Esc to cancel" />
      </box>
    </window>
  );
}
