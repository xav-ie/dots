import type { Accessor } from "ags";
import { Gdk, Gtk } from "ags/gtk4";
import GLib from "gi://GLib";

// The focusable widgets under `w`, in tab order. A focusable widget is a single
// tab stop, so it's treated as a leaf (we don't descend into composites like
// SpinButton and pick up their internal text); unmapped / insensitive branches
// (a hidden row, a disabled button) are skipped so the cycle matches what the
// user actually sees.
function tabStops(w: Gtk.Widget, out: Gtk.Widget[] = []): Gtk.Widget[] {
  for (let c = w.get_first_child(); c; c = c.get_next_sibling()) {
    if (!c.get_mapped() || !c.get_sensitive()) continue;
    if (c.get_focusable()) out.push(c);
    else tabStops(c, out);
  }
  return out;
}

export interface ModalFocusTrapOpts {
  // The dialog panel to trap within (default: the controller root). A thunk so it
  // can read a ref assigned after this runs.
  panel?: () => Gtk.Widget | null | undefined;
  // Where focus lands when the modal opens (default: the first tab stop). Use it
  // to land on the primary action, or to skip a destructive first control.
  initial?: () => Gtk.Widget | null | undefined;
  // Optional Enter/Return action (e.g. the primary button). Omit when the modal
  // owns Enter itself — a search entry with its own onActivate.
  onActivate?: () => void;
  // When false, install the Tab trap but DON'T grab focus on open — the caller
  // owns initial focus (e.g. the floating editor keeps focus on its title). This
  // makes it a *soft* trap: the capture controller only engages while focus is
  // already inside, so Tab can't leak out, but mouse interaction stays free.
  autoFocus?: boolean;
}

// Lock keyboard focus inside a modal overlay. Tab / Shift+Tab cycle through the
// panel's focusables and never escape to the widgets behind it; focus is moved
// into the panel whenever `open` flips true — that grab is what puts the capture
// controller on the key-event path, so the trap actually holds. Call from the
// backdrop root's ref callback:
//   $={(r) => { root = r; modalFocusTrap(r, open, { onActivate: send }) }}
// Generalises the hand-rolled InviteDialog trap. With `autoFocus: false` it
// becomes a *soft* trap for a non-modal surface (the floating event editor):
// Tab stays inside while you're editing, but mouse interaction with the rest of
// the app is untouched and the caller keeps its own initial focus.
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
      if (
        opts.onActivate &&
        (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter)
      ) {
        opts.onActivate();
        return true;
      }
      return false;
    },
  );
  root.add_controller(key);

  if (opts.autoFocus !== false)
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
