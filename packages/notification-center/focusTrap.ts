import type { Accessor } from "ags";
import { Gdk, Gtk } from "ags/gtk4";
import GLib from "gi://GLib";

// The focusable widgets under `w`, in tab order. Unmapped / insensitive
// branches (a hidden row, a disabled button) are skipped so the cycle matches
// what the user actually sees. Unlike a strict leaf walk we keep descending
// past a focusable widget: this panel's only nested focusables are a
// notification row's own action buttons (the row is focusable *and* contains
// focusable buttons), and we want both to be tab stops. The leaf widgets here
// (switch, slider, button) expose no inner Gtk.Widget children, so descending
// into them adds nothing.
function tabStops(w: Gtk.Widget, out: Gtk.Widget[] = []): Gtk.Widget[] {
  for (let c = w.get_first_child(); c; c = c.get_next_sibling()) {
    if (!c.get_mapped() || !c.get_sensitive()) continue;
    if (c.get_focusable()) out.push(c);
    tabStops(c, out);
  }
  return out;
}

// Move focus to the tab stop adjacent to `from` within `root` (backward by
// default). Used when the focused widget is about to be destroyed — e.g. the
// last notification on Backspace, which has no list sibling to receive focus, so
// it hands off to the previous trap stop (the Clear All button) before dismiss.
export function focusAdjacent(
  root: Gtk.Widget,
  from: Gtk.Widget,
  back = true,
): void {
  const stops = tabStops(root);
  if (!stops.length) return;
  let idx = stops.indexOf(from);
  if (idx < 0) idx = stops.findIndex((w) => w.has_focus);
  if (idx < 0) {
    stops[0].grab_focus();
    return;
  }
  const next = (idx + (back ? -1 : 1) + stops.length) % stops.length;
  stops[next].grab_focus();
}

export interface ModalFocusTrapOpts {
  // The region to trap within (default: the controller root). A thunk so it can
  // read a ref assigned after this runs.
  panel?: () => Gtk.Widget | null | undefined;
  // Where focus lands when the modal opens (default: the first tab stop). Use it
  // to land on a more useful control than the first one in tab order.
  initial?: () => Gtk.Widget | null | undefined;
}

// Lock keyboard focus inside an overlay. Tab / Shift+Tab cycle through the
// panel's focusables (wrapping at both ends) and never escape to the widgets
// behind it; focus is moved into the panel whenever `open` flips true. Ported
// from morrow's focusTrap so the center's Tab traversal behaves the same: a
// capture-phase controller that walks the live tab stops itself, rather than
// leaning on GTK's default traversal (which stalls at the ScrolledWindow).
export function modalFocusTrap(
  root: Gtk.Widget,
  open: Accessor<boolean>,
  opts: ModalFocusTrapOpts = {},
): void {
  const within = () => opts.panel?.() ?? root;

  const key = new Gtk.EventControllerKey();
  key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
  key.connect(
    "key-pressed",
    (
      _c: Gtk.EventControllerKey,
      keyval: number,
      _code: number,
      state: Gdk.ModifierType,
    ) => {
      if (keyval === Gdk.KEY_Tab || keyval === Gdk.KEY_ISO_Left_Tab) {
        const stops = tabStops(within());
        if (!stops.length) return true; // nothing to move to, but don't escape
        const back =
          keyval === Gdk.KEY_ISO_Left_Tab ||
          !!(state & Gdk.ModifierType.SHIFT_MASK);
        const idx = stops.findIndex((w) => w.has_focus);
        const next = (idx + (back ? -1 : 1) + stops.length) % stops.length;
        stops[next].grab_focus();
        return true;
      }
      return false;
    },
  );
  root.add_controller(key);

  open.subscribe(() => {
    if (!open.get()) return;
    // Deferred so dynamically-built rows are realized before we grab.
    GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
      const target = opts.initial?.() ?? tabStops(within())[0];
      target?.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  });
}
