// Keyboard selection for the result-list modes (app / clipboard / emoji). Focus
// stays on the search entry the whole time; instead of walking GTK focus into the
// rows, each mode tracks a `selected` index here and paints a `.sel` class on the
// matching row. That way the result Enter would pick is *always* highlighted —
// starting at the top the moment results render — and the arrows just slide that
// highlight while you keep typing.
import { Accessor, createComputed, createEffect, createState } from "ags";
import { Gtk } from "ags/gtk4";

export interface Selection<T> {
  // The currently highlighted item (what Enter picks), or undefined when empty.
  current: Accessor<T | undefined>;
  // Move the highlight by `delta` rows, clamped to the list (no wrap — a launcher
  // list shouldn't loop from bottom back to top under the arrow keys).
  move: (delta: number) => void;
  // Reactive class for a row: `${base} sel` while this item is highlighted.
  cls: (item: T, base: string) => Accessor<string>;
}

// `items` is the live, ordered result list. The highlight resets to the top
// whenever that list changes (a new query, a frecency reload on show), matching
// every other "type to filter" launcher.
export function createSelection<T>(items: Accessor<T[]>): Selection<T> {
  const [index, setIndex] = createState(0);

  // Snap back to the first result on every list change.
  createEffect(() => {
    items();
    setIndex(0);
  });

  const current = createComputed(() => items()[index()]);

  const move = (delta: number) => {
    const n = items().length;
    if (n === 0) return;
    setIndex(Math.max(0, Math.min(n - 1, index() + delta)));
  };

  const cls = (item: T, base: string) =>
    createComputed(() => (current() === item ? `${base} sel` : base));

  return { current, move, cls };
}

// Scroll `container` (the box inside a ScrolledWindow) so `widget` is fully
// visible, nudging only as far as needed. Coordinates are taken relative to the
// container, whose offset is exactly the scrolled child's vadjustment value.
export function scrollIntoView(
  scroll: Gtk.ScrolledWindow,
  container: Gtk.Widget,
  widget?: Gtk.Widget | null,
): void {
  if (!widget) return;
  const vadj = scroll.get_vadjustment();
  if (!vadj) return;
  const [ok, rect] = widget.compute_bounds(container);
  if (!ok) return;
  const M = 8; // breathing room above/below the highlighted row
  const top = rect.get_y();
  const bottom = top + rect.get_height();
  const value = vadj.get_value();
  const page = vadj.get_page_size();
  if (top - M < value) vadj.set_value(Math.max(0, top - M));
  else if (bottom + M > value + page) vadj.set_value(bottom + M - page);
}
