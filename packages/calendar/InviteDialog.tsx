import { For, createComputed } from "ags";
import { Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import Graphene from "gi://Graphene";
import { iconPx } from "./zoom";
import { modalFocusTrap } from "./focusTrap";
import { nameOf } from "./contacts";
import { commitInvites, syncNow } from "./store";
import {
  clearDraft,
  draftHolder,
  draftInvites,
  inviteDialog,
  setInviteDialog,
  setSelected,
} from "./state";

// "Do you want to send the invite?" confirm dialog shown when closing an event
// that has unsent draft invitees.
export default function InviteDialog() {
  let panel: Gtk.Box;
  let root: Gtk.Box;
  let sendBtn: Gtk.Button;
  const rows = createComputed(() => draftInvites());

  const close = () => setInviteDialog(false);
  const discard = () => {
    clearDraft();
    close();
    setSelected(null);
  };
  const send = () => {
    if (draftHolder.event) commitInvites(draftHolder.event, draftInvites.get());
    clearDraft();
    close();
    setSelected(null);
    // Sync after a short delay so Google has time to propagate the invite to
    // the invitee's calendar before we re-fetch.
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 3000, () => {
      void syncNow();
      return GLib.SOURCE_REMOVE;
    });
  };

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) close();
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => {
        root = r;
        // Trap focus among the actions; Enter confirms (Send) and focus lands on
        // Send when the dialog opens.
        modalFocusTrap(r, inviteDialog, {
          panel: () => panel,
          initial: () => sendBtn,
          onActivate: send,
        });
      }}
      visible={inviteDialog((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="invite-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={4}
      >
        <label
          class="dialog-title"
          label="Do you want to send the invite?"
          halign={Gtk.Align.START}
          wrap
        />
        <label
          class="dialog-sub muted"
          label="Send the invite to keep the change, keep editing, or discard the invite."
          halign={Gtk.Align.START}
          wrap
        />
        <box
          class="dialog-people"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={2}
        >
          <For each={rows}>
            {(email: string) => (
              <box class="participant" spacing={8}>
                <image
                  iconName="avatar-default-symbolic"
                  pixelSize={iconPx(18)}
                  valign={Gtk.Align.CENTER}
                />
                <label
                  label={nameOf(email)}
                  halign={Gtk.Align.START}
                  hexpand
                  ellipsize={3}
                />
              </box>
            )}
          </For>
        </box>
        <box class="dialog-actions" spacing={8}>
          <button class="dialog-discard" onClicked={discard}>
            <label label="Discard invite" />
          </button>
          <box hexpand />
          <button class="dialog-keep" onClicked={close}>
            <label label="Continue editing" />
          </button>
          <button
            class="dialog-send"
            onClicked={send}
            $={(b: Gtk.Button) => (sendBtn = b)}
          >
            <label label="Send invite" />
          </button>
        </box>
      </box>
    </box>
  );
}
