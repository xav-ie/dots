import { Astal, Gtk } from "ags/gtk4";

const { TOP } = Astal.WindowAnchor;

const MODES = {
  insert: {
    icon: "media-removable-symbolic",
    title: "Insert your YubiKey",
    detail: "sudo is waiting for it · 30s, then your password",
  },
  touch: {
    icon: "dialog-password-symbolic",
    title: "Touch your YubiKey",
    detail: "It's blinking and waiting for a tap",
  },
};

export type Mode = keyof typeof MODES;

// A small top-centre layer surface, the Linux twin of nox's yubikey-touch-prompt.
// It never takes the keyboard (Keymode.NONE), so it can sit over the PIN
// pinentry or the terminal sudo runs in without stealing focus.
export default function Popup() {
  let icon: Gtk.Image;
  let title: Gtk.Label;
  let detail: Gtk.Label;

  const win = (
    <window
      name="yubikey-touch-popup"
      namespace="yubikey-touch-popup"
      anchor={TOP}
      marginTop={24}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.NONE}
      visible={false}
    >
      <box class="panel" spacing={16}>
        <image $={(ref) => (icon = ref)} pixelSize={32} valign={Gtk.Align.CENTER} />
        <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER} spacing={2}>
          <label $={(ref) => (title = ref)} class="title" xalign={0} />
          <label $={(ref) => (detail = ref)} class="detail" xalign={0} />
        </box>
      </box>
    </window>
  ) as Astal.Window;

  return {
    win,
    show(mode: Mode | null) {
      if (mode === null) {
        win.visible = false;
        return;
      }
      const text = MODES[mode];
      icon.iconName = text.icon;
      title.label = text.title;
      detail.label = text.detail;
      win.visible = true;
    },
  };
}
