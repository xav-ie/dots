import { Accessor, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";

// GTK4 exposes widgets to screen readers (Orca, via AT-SPI) through the
// Gtk.Accessible interface, but it does NOT promote a widget's tooltip to its
// accessible name. So icon-only buttons and color-coded chips — which carry no
// text label — are announced as a bare "button" with no name. This helper sets
// an explicit accessible name (and optional description) on such widgets.
//
// Call it from a `$=` ref callback: `$={(b) => a11y(b, "Dismiss")}`. The label
// may be a plain string or a reactive Accessor (e.g. a state-derived "Show
// calendar" / "Hide calendar"), in which case the name tracks the value.

type Text = string | Accessor<string>;

function bind(w: Gtk.Widget, prop: Gtk.AccessibleProperty, text: Text) {
  if (text instanceof Accessor) {
    const apply = () => w.update_property([prop], [text.get()]);
    apply();
    onCleanup(text.subscribe(apply));
  } else {
    w.update_property([prop], [text]);
  }
}

export function a11y(w: Gtk.Widget, label: Text, description?: Text) {
  bind(w, Gtk.AccessibleProperty.LABEL, label);
  if (description !== undefined)
    bind(w, Gtk.AccessibleProperty.DESCRIPTION, description);
}
