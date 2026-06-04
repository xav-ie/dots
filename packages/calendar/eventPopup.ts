import { Gtk } from "ags/gtk4";
import { unionBounds } from "./chipRegistry";
import { setFloatAnchor, setSelected, type Selection } from "./state";

// Select an event. When the right pane is open it shows there; otherwise the
// FloatingEditor overlay shows it, anchored next to the chip it was opened from.
// `spanWidgets` (a multi-day event's segments across day columns) anchors the
// editor to the whole event's width, not just the clicked day's segment.
export function pickEvent(
  widget: Gtk.Widget,
  sel: Selection,
  spanWidgets?: Gtk.Widget[],
) {
  const root = widget.get_root() as Gtk.Widget | null;
  if (root)
    setFloatAnchor(
      unionBounds(spanWidgets?.length ? spanWidgets : [widget], root),
    );
  setSelected(sel);
}
