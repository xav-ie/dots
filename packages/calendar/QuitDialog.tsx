import { Gtk } from "ags/gtk4";
import Graphene from "gi://Graphene";
import app from "ags/gtk4/app";
import { modalFocusTrap } from "./focusTrap";
import { quitConfirmOpen, setQuitConfirmOpen } from "./state";

const START = Gtk.Align.START;
const CENTER = Gtk.Align.CENTER;

// "Quit Calendar?" confirm. Escape (with no modal open and nothing selected)
// raises this instead of quitting outright. Cancel / backdrop click / Escape
// dismiss it; Quit exits. Focus defaults to Cancel (the first action), so a
// reflexive Enter or second Escape keeps the app open rather than quitting.
export default function QuitDialog() {
  let panel: Gtk.Box;
  let root: Gtk.Box;

  const close = () => setQuitConfirmOpen(false);

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) close();
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => {
        root = r;
        // Trap focus on the two actions; no onActivate, so Enter activates the
        // focused button (Cancel by default) rather than always quitting.
        modalFocusTrap(r, quitConfirmOpen, { panel: () => panel });
      }}
      visible={quitConfirmOpen((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="invite-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={CENTER}
        valign={CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={4}
      >
        <label class="dialog-title" label="Quit Calendar?" halign={START} />
        <label
          class="dialog-sub muted"
          label="Reminders for upcoming events stop until you reopen it."
          halign={START}
          wrap
        />
        <box class="dialog-actions" spacing={8}>
          <box hexpand />
          <button class="dialog-keep" onClicked={close}>
            <label label="Cancel" />
          </button>
          <button class="dialog-send" onClicked={() => app.quit()}>
            <label label="Quit" />
          </button>
        </box>
      </box>
    </box>
  );
}
