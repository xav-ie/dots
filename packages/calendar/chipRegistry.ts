// Registry of rendered event-chip widgets, keyed by event id + day, plus the
// geometry that reads it: the Vimium hints, the multi-day hover-highlight, and
// the floating editor's anchor all locate chips through here. Shared by WeekView
// (which registers chips), FloatingEditor, and eventPopup.
import { Gtk } from "ags/gtk4";
import type { FloatAnchor } from "./state";

export const chipReg = new Map<string, Gtk.Widget>();

export const chipKey = (id: string | undefined, date: Date) =>
  `${id}@${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;

// All chips of one event share the `${id}@` key prefix (a multi-day event renders
// a chip per day).
function chipsOf(id: string): Gtk.Widget[] {
  const prefix = `${id}@`;
  const out: Gtk.Widget[] = [];
  for (const [key, w] of chipReg) if (key.startsWith(prefix)) out.push(w);
  return out;
}

// Bounding box (in `root` coords) enclosing all `widgets`, or null if none can be
// measured. The one place chip bounds are unioned (anchors + re-anchoring).
export function unionBounds(
  widgets: Gtk.Widget[],
  root: Gtk.Widget,
): FloatAnchor | null {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  let any = false;
  for (const w of widgets) {
    const [ok, b] = w.compute_bounds(root);
    if (!ok) continue;
    any = true;
    minX = Math.min(minX, b.get_x());
    minY = Math.min(minY, b.get_y());
    maxX = Math.max(maxX, b.get_x() + b.get_width());
    maxY = Math.max(maxY, b.get_y() + b.get_height());
  }
  if (!any) return null;
  return {
    x: minX,
    y: minY,
    w: maxX - minX,
    h: maxY - minY,
    rw: root.get_width(),
    rh: root.get_height(),
  };
}

// Highlight every segment of a multi-day event when any one is hovered.
export function setSpanHover(id: string | undefined, on: boolean) {
  if (!id) return;
  for (const w of chipsOf(id)) {
    if (on) w.add_css_class("span-hover");
    else w.remove_css_class("span-hover");
  }
}

// Every rendered segment of a multi-day event (full-width anchor for the editor).
export const spanWidgets = (id: string | undefined): Gtk.Widget[] =>
  id ? chipsOf(id) : [];

// Live bounds of a selected event's chip(s), re-measured from the registry — so
// the floating editor can re-anchor after a panel toggle reflows the grid (chips
// move/widen or are re-created). `span` unions all of a multi-day event's
// segments (all-day bars); otherwise just this day's. Null when the chip isn't
// currently rendered (e.g. month view) so the caller keeps its last anchor.
export function liveAnchor(
  id: string | undefined,
  date: Date,
  span: boolean,
): FloatAnchor | null {
  if (!id) return null;
  const single = chipReg.get(chipKey(id, date));
  const widgets = span ? chipsOf(id) : single ? [single] : [];
  if (!widgets.length) return null;
  const root = widgets[0].get_root() as Gtk.Widget | null;
  return root ? unionBounds(widgets, root) : null;
}
