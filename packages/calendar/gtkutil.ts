// Small GTK helpers shared by the imperatively-rebuilt lists/grids.
import { createRoot } from "ags";
import { Gtk } from "ags/gtk4";

// Anything that holds removable children (Gtk.Box, Gtk.Fixed, …).
type Container = {
  get_first_child(): Gtk.Widget | null;
  remove(child: Gtk.Widget): void;
};

// Remove every child of a container — the imperative list/grid reset repeated
// across the views.
export function clearChildren(box: Container): void {
  let c = box.get_first_child();
  while (c) {
    const next = c.get_next_sibling();
    box.remove(c);
    c = next;
  }
}

// Rebuild a container's contents inside a fresh reactive root: clear the old
// children, dispose the previous root, then run `build` in a new createRoot.
// Returns the new disposer (pass the previous one in to chain). Encapsulates the
// clear + dispose-prev + createRoot dance several components repeat — and ensures
// imperatively-created widgets have a tracking context for their cleanup.
export function rebuildIn(
  box: Container,
  prevDispose: (() => void) | null,
  build: () => void,
): () => void {
  clearChildren(box);
  if (prevDispose) prevDispose();
  let dispose: () => void = () => {};
  createRoot((d) => {
    dispose = d;
    build();
  });
  return dispose;
}
