import { createComputed, createRoot } from "ags";
import { Gtk } from "ags/gtk4";
import { clearChildren } from "./gtkutil";
import { modalFocusTrap } from "./focusTrap";
import GLib from "gi://GLib";
import EventInfo from "./EventInfo";
import { liveAnchor } from "./chipRegistry";
import {
  floatAnchor,
  leftVisible,
  rightVisible,
  selected,
  setFloatAnchor,
} from "./state";
import { iconPx, zoom } from "./zoom";

const EW_BASE = 320; // editor width at 100% zoom
const EH_BASE = 680; // max editor height (it scrolls past this)
const GAP = 8;
// Current width/height, scaled with zoom so the card fits the scaled content
// (a fixed width would clip and warn "needs at least N" as the content grows).
const ew = () => Math.round(EW_BASE * zoom.get());
const eh = () => Math.round(EH_BASE * zoom.get());

// Floating event editor shown (as an overlay card, not a popover) when an event
// is selected and the right pane is collapsed. An overlay has no autohide /
// popdown behavior, so editing — adding participants, etc. — can't dismiss it.
// It positions itself next to the chip it was opened from.
export default function FloatingEditor() {
  let wrap: Gtk.Box;
  let body: Gtk.Box;
  let dispose: (() => void) | null = null;
  const shown = createComputed(() => !!selected() && !rightVisible());

  function position() {
    const a = floatAnchor.get();
    if (!a) {
      // No chip anchor (command/keyboard-created): float at the top-right.
      wrap.set_halign(Gtk.Align.END);
      wrap.set_valign(Gtk.Align.START);
      wrap.set_margin_start(0);
      wrap.set_margin_top(12);
      return;
    }
    wrap.set_halign(Gtk.Align.START);
    wrap.set_valign(Gtk.Align.START);
    // Actual editor height (its content, capped where it starts scrolling), so a
    // short editor isn't shoved up the screen by reserving the full max height.
    const w = ew();
    const natH = body.measure(Gtk.Orientation.VERTICAL, w)[1];
    const h = Math.min(natH > 0 ? natH : eh(), eh());
    // Horizontal: prefer the right of the chip; flip to its left if it overflows.
    let mx = a.x + a.w + GAP;
    if (mx + w + 8 > a.rw) mx = a.x - w - GAP;
    mx = Math.max(8, Math.min(mx, a.rw - w - 8));
    // Vertical: center the editor on the chip, then clamp to keep it on screen.
    const my = Math.max(8, Math.min(a.y + a.h / 2 - h / 2, a.rh - h - 8));
    wrap.set_margin_start(mx);
    wrap.set_margin_top(my);
  }

  // Re-measure the selected chip from the grid (it moves/re-renders when a panel
  // toggles), update the anchor, and reposition. Keeps the last anchor when the
  // chip isn't currently rendered (e.g. month view) rather than jumping away.
  function reposition() {
    if (!selected.get() || rightVisible.get()) return;
    const sel = selected.get()!;
    const span = !!(sel.ev.allDay && sel.ev.endDate);
    const fresh = liveAnchor(sel.ev.id, sel.date, span);
    if (fresh) setFloatAnchor(fresh);
    position();
  }

  // A panel open/close reflows the grid over a few frames; reposition a few times
  // so the editor settles onto the chip's final spot once the toggle completes.
  function repositionSoon() {
    reposition();
    for (const delay of [60, 180, 360])
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, delay, () => {
        reposition();
        return GLib.SOURCE_REMOVE;
      });
  }

  function render() {
    clearChildren(body);
    if (dispose) dispose();
    const sel = selected.get();
    if (!sel || rightVisible.get()) return;
    createRoot((d) => {
      dispose = d;
      body.append(EventInfo(sel) as Gtk.Widget);
    });
    repositionSoon(); // after the content is in + after the layout settles
  }

  return (
    <box
      class="floating-editor-wrap"
      halign={Gtk.Align.START}
      valign={Gtk.Align.START}
      visible={shown((v) => v)}
      $={(r: Gtk.Box) => {
        wrap = r;
        // Soft focus trap: keep Tab within the card's fields so it can't leak to
        // the grid chips behind it. autoFocus off — it's a non-modal card (mouse
        // stays free) and EventInfo's title field owns initial focus.
        modalFocusTrap(r, shown, { panel: () => body, autoFocus: false });
      }}
    >
      <scrolledwindow
        class="floating-editor"
        widthRequest={iconPx(EW_BASE)}
        maxContentHeight={iconPx(EH_BASE)}
        propagateNaturalHeight
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
        $={(sw: Gtk.ScrolledWindow) => sw.set_propagate_natural_width(false)}
      >
        <box
          class="detail-body"
          orientation={Gtk.Orientation.VERTICAL}
          $={(ref: Gtk.Box) => {
            body = ref;
            render();
            selected.subscribe(render);
            rightVisible.subscribe(render);
            // Left panel toggles don't change what's shown, but they shift the
            // grid horizontally — re-anchor once the toggle settles.
            leftVisible.subscribe(repositionSoon);
            // Zoom changes the card width and reflows the grid → re-measure/anchor.
            zoom.subscribe(repositionSoon);
          }}
        />
      </scrolledwindow>
    </box>
  );
}
