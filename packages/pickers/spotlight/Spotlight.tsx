import { createState } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import GLib from "gi://GLib";
import PickerWindow, { closePicker } from "../lib/window";
import { onRequest } from "./controller";
import { ModeHandle } from "./modes/types";
import AppMode from "./modes/AppMode";
import ClipboardMode from "./modes/ClipboardMode";
import EmojiMode from "./modes/EmojiMode";
import BluetoothMode from "./modes/BluetoothMode";
import PowerMode from "./modes/PowerMode";

const MODES = [
  { id: "app", label: "Apps", icon: "view-grid-symbolic", Mode: AppMode },
  {
    id: "clipboard",
    label: "Clipboard",
    icon: "edit-paste-symbolic",
    Mode: ClipboardMode,
  },
  { id: "emoji", label: "Emoji", icon: "face-smile-symbolic", Mode: EmojiMode },
  {
    id: "bluetooth",
    label: "Bluetooth",
    icon: "bluetooth-symbolic",
    Mode: BluetoothMode,
  },
  {
    id: "power",
    label: "Power",
    icon: "system-shutdown-symbolic",
    Mode: PowerMode,
  },
] as const;

type ModeId = (typeof MODES)[number]["id"];
const IDS = MODES.map((m) => m.id) as ModeId[];

export default function Spotlight() {
  const handles: Partial<Record<ModeId, ModeHandle>> = {};
  const [mode, setMode] = createState<ModeId>("app");

  const close = () => closePicker("spotlight", true);
  const getWin = () => app.get_window("spotlight");

  // Run the active mode's onShow on the next idle tick — late enough that a
  // freshly-revealed mode box is realized and grab_focus lands.
  function showActive() {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      handles[mode.get()]?.onShow();
      return GLib.SOURCE_REMOVE;
    });
  }

  function switchTo(id: ModeId) {
    if (id === mode.get()) return;
    setMode(id);
    // Grab focus synchronously (border paints with the revealed box); showActive
    // still runs the mode's onShow for its state refresh and idle-grab fallback.
    handles[id]?.focus?.();
    showActive();
  }

  function cycle(delta: number) {
    const i = IDS.indexOf(mode.get());
    switchTo(IDS[(i + delta + IDS.length) % IDS.length]);
  }

  // Keybinds (app.ts → controller) carry a mode. Same mode while visible →
  // hide (toggle off); otherwise switch to it and present.
  onRequest((id) => {
    const win = getWin();
    if (!win) return;
    const requested = (IDS as string[]).includes(id)
      ? (id as ModeId)
      : mode.get();
    if (win.visible && requested === mode.get()) {
      win.visible = false;
      return;
    }
    setMode(requested);
    if (win.visible) showActive();
    else win.present(); // present → onNotifyVisible → PickerWindow.onShow
  });

  // Ctrl+Left/Right (and Ctrl+Page Up/Down) cycle modes. Handled in the CAPTURE
  // phase (see the controller in the markup) so the search entry doesn't eat
  // them as word-navigation before we get a look.
  function onSwitchKey(keyval: number, modk: number) {
    if ((modk & Gdk.ModifierType.CONTROL_MASK) === 0) return false;
    if (keyval === Gdk.KEY_Left || keyval === Gdk.KEY_Page_Up) {
      cycle(-1);
      return true;
    }
    if (keyval === Gdk.KEY_Right || keyval === Gdk.KEY_Page_Down) {
      cycle(1);
      return true;
    }
    return false;
  }

  // Everything else is delegated to the active mode (bubble phase, after the
  // focused widget has had its chance).
  function onKey(
    keyval: number,
    modk: number,
    controller: Gtk.EventControllerKey,
  ) {
    return handles[mode.get()]?.onKey(keyval, modk, controller);
  }

  return (
    <PickerWindow
      name="spotlight"
      resident
      spacing={10}
      onShow={() => handles[mode.get()]?.onShow()}
      onKey={onKey}
    >
      <Gtk.EventControllerKey
        propagationPhase={Gtk.PropagationPhase.CAPTURE}
        onKeyPressed={(_c, keyval, _k, modk) => onSwitchKey(keyval, modk)}
      />
      <box class="tabs" spacing={4} homogeneous>
        {MODES.map((m) => (
          <button
            class={mode((cur) => (cur === m.id ? "tab active" : "tab"))}
            // Driven by Ctrl+←/→ and clicks only; keep it out of the focus chain
            // so GTK never parks the focus ring here while a mode swap reparents
            // focus (the "Apps" tab outline flicker).
            focusable={false}
            onClicked={() => switchTo(m.id)}
          >
            <box spacing={6} halign={Gtk.Align.CENTER}>
              <image iconName={m.icon} pixelSize={24} />
              <label label={m.label} />
            </box>
          </button>
        ))}
      </box>
      <Gtk.Separator />
      {MODES.map((m) => (
        // Vertical wrapper so the mode content fills the panel width — a bare
        // (horizontal) box would let it collapse to its natural width, which
        // shrinks the emoji grid below its 10 columns.
        <box
          orientation={Gtk.Orientation.VERTICAL}
          visible={mode((cur) => cur === m.id)}
        >
          {m.Mode({
            register: (h) => (handles[m.id] = h),
            close,
            getWin,
          })}
        </box>
      ))}
    </PickerWindow>
  );
}
