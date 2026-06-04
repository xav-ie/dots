import { createRoot } from "ags";
import { Gtk } from "ags/gtk4";
import { clearChildren } from "./gtkutil";
import { modalFocusTrap } from "./focusTrap";
import Graphene from "gi://Graphene";
import {
  recurScopeHolder,
  recurScopeOpen,
  resolveRecurScope,
  type RecurScope,
} from "./state";

const START = Gtk.Align.START;
const SCOPES: { key: RecurScope; label: string }[] = [
  { key: "this", label: "This event" },
  { key: "following", label: "This and following events" },
  { key: "all", label: "All events" },
];

// For a calendar move, spell out what each scope does to the old vs new calendar
// (the inline form of a two-column "old / new" chooser).
function moveSub(key: RecurScope, dest: string): string {
  if (key === "this") return `Only this occurrence moves to ${dest}`;
  if (key === "following") return `This and later occurrences move to ${dest}`;
  return `The whole series moves to ${dest}`;
}

// "This is a repeating event" scope chooser, shared by edit / delete / move.
// Built once; re-seeded from recurScopeHolder each time it opens. Resolves the
// askRecurScope() promise with the chosen scope (or null on cancel).
export default function RecurScopeDialog() {
  let panel: Gtk.Box;
  let root: Gtk.Box;
  let titleLbl: Gtk.Label;
  let listBox: Gtk.Box;
  let chosen: RecurScope = "this";
  let disposeList: (() => void) | null = null;

  const close = (scope: RecurScope | null) => resolveRecurScope(scope);

  const render = () => {
    const h = recurScopeHolder;
    titleLbl.set_label(
      h.verb === "move"
        ? `Move “${h.title}” to ${h.dest}`
        : h.verb === "delete"
          ? `Delete “${h.title}”?`
          : `Edit “${h.title}”`,
    );
    clearChildren(listBox);
    if (disposeList) disposeList();
    // Rows are built imperatively from a subscribe callback, so give them a root
    // (cheap insurance: their props are static today, but a future reactive prop
    // would otherwise warn "out of tracking context").
    createRoot((dispose) => {
      disposeList = dispose;
      const allowed = SCOPES.filter((s) => h.allow[s.key]);
      chosen = allowed[0]?.key ?? "this";
      let group: Gtk.CheckButton | null = null;
      for (const s of allowed) {
        const cb = new Gtk.CheckButton();
        cb.add_css_class("scope-opt");
        if (group) cb.set_group(group);
        else group = cb;
        const sub = h.verb === "move" ? moveSub(s.key, h.dest) : "";
        const inner = (
          <box orientation={Gtk.Orientation.VERTICAL}>
            <label class="scope-label" label={s.label} halign={START} />
            {sub ? (
              <label class="scope-sub muted" label={sub} halign={START} />
            ) : (
              <box />
            )}
          </box>
        ) as Gtk.Widget;
        cb.set_child(inner);
        cb.connect("toggled", () => {
          if (cb.get_active()) chosen = s.key;
        });
        cb.set_active(s.key === chosen);
        listBox.append(cb);
      }
    });
  };
  recurScopeOpen.subscribe(() => recurScopeOpen.get() && render());

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) close(null);
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => {
        root = r;
        // Trap focus among the scope radios + actions; Enter confirms (OK), and
        // focus lands on the first option (the default scope) when it opens.
        modalFocusTrap(r, recurScopeOpen, {
          panel: () => panel,
          onActivate: () => close(chosen),
        });
      }}
      visible={recurScopeOpen((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="recur-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={10}
      >
        <label
          class="dialog-title"
          $={(l: Gtk.Label) => (titleLbl = l)}
          label="Repeating event"
          halign={START}
          wrap
        />
        <box
          class="scope-list"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={4}
          $={(b: Gtk.Box) => (listBox = b)}
        />
        <box class="dialog-actions" spacing={8}>
          <box hexpand />
          <button class="dialog-keep" onClicked={() => close(null)}>
            <label label="Cancel" />
          </button>
          <button class="dialog-send" onClicked={() => close(chosen)}>
            <label label="OK" />
          </button>
        </box>
      </box>
    </box>
  );
}
