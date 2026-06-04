import { Gtk } from "ags/gtk4";
import Graphene from "gi://Graphene";
import { SHORTCUT_GROUPS } from "./shortcuts";
import { setShortcutsOpen, shortcutsOpen } from "./state";

const START = Gtk.Align.START;

// Full keyboard-shortcut reference, opened with "?" and dismissed by clicking
// the backdrop (or Escape, handled in Calendar.tsx).
export default function ShortcutsDialog() {
  let panel: Gtk.Box;
  let root: Gtk.Box;

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y })))
      setShortcutsOpen(false);
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => (root = r)}
      visible={shortcutsOpen((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="shortcuts-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={10}
      >
        <label class="dialog-title" label="Keyboard shortcuts" halign={START} />
        <box class="shortcuts-cols" spacing={28}>
          {SHORTCUT_GROUPS.map((g) => (
            <box orientation={Gtk.Orientation.VERTICAL} spacing={7} hexpand>
              <label class="shortcuts-group" label={g.title} halign={START} />
              {g.items.map((s) => (
                <box spacing={10}>
                  <label
                    class="shortcut-name"
                    label={s.name}
                    halign={START}
                    hexpand
                  />
                  <box spacing={3}>
                    {s.keys.map((k) => (
                      <label class="kbd" label={k} />
                    ))}
                  </box>
                </box>
              ))}
            </box>
          ))}
        </box>
      </box>
    </box>
  );
}
