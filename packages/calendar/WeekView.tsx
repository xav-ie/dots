import { For, createComputed, createRoot, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { clearChildren } from "./gtkutil";
import { chipKey, chipReg, setSpanHover, spanWidgets } from "./chipRegistry";
import GLib from "gi://GLib";
import {
  HOUR_HEIGHT,
  HOURS,
  NOW_HOUR,
  TODAY,
  addDays,
  addMonths,
  fmtDow,
  fmtHour,
  fmtMonthYear,
  fmtTime,
  nowHour,
  sameDay,
  startOfWeek,
  tzFromZone,
  weekDays,
} from "./datetime";
import {
  TIMEZONES,
  allDayAsCalEvent,
  allDayOn,
  calColor,
  eventColor,
  isBirthday,
  isRecurringEvent,
  eventsOn,
  personBusy,
  spanPart,
  type CalEvent,
} from "./data";
import { googleConfigured } from "./gmap";
import { personColor } from "./palette";
import { iconPx, registerZoomScroll, zoom } from "./zoom";
import {
  createEvent,
  liveEvent,
  rev,
  setAllDay,
  setEventMove,
  setEventTime,
} from "./store";
import {
  accounts,
  addTimezone,
  allDayExpanded,
  anchor,
  defaultCal,
  draftInvites,
  flashId,
  freeBusy,
  freeBusyLoading,
  hiddenCals,
  invitePreviewOff,
  savedPreview,
  leftVisible,
  makeDefaultTimezone,
  refreshFreeBusy,
  removeTimezone,
  rightVisible,
  selected,
  setAllDayExpanded,
  setAnchor,
  setHintMode,
  setLeftVisible,
  setRightVisible,
  setSelected,
  setView,
  sidebarToggle,
  timezones,
  view,
} from "./state";
import { pickEvent } from "./eventPopup";
import { Row } from "./SuggestField";
import MonthView from "./MonthView";

const START = Gtk.Align.START;
// Displayed timezones with their column index, primary-relative offset, and a
// `last` flag (the rightmost column drops its border so it doesn't stack with
// the time-axis divider).
const tzList = createComputed(() => {
  zoom(); // rebuild the gutter columns (HOUR_HEIGHT-positioned) on zoom
  const ts = timezones();
  const caretCol = Math.min(1, ts.length - 1); // the all-day toggle's column
  return ts.map((tz, i) => ({
    tz,
    i,
    rel: tz.utc - ts[0].utc,
    last: i === ts.length - 1,
    caret: i === caretCol,
  }));
});
// Column width grows with the widest label (header abbreviation or hour label),
// so long codes like "GMT−12" / fractional-offset times aren't clipped.
const tzColW = createComputed(() => {
  const z = zoom(); // labels scale with the font, so the gutter must too
  const tzs = timezones();
  const frac = tzs.some((t) => !Number.isInteger(t.utc - tzs[0].utc));
  const hourChars = frac ? 8 : 5; // "12:30 AM" vs "12 PM"
  const maxChars = Math.max(hourChars, ...tzs.map((t) => t.label.length));
  return Math.round(Math.max(46, Math.round(maxChars * 7.5) + 14) * z);
});
// N columns + the (N-1) inner 1px borders between timezones (the last column
// has none), so the gutters match the time-axis width.
const gutterW = createComputed(() => {
  const n = timezones().length;
  return n * tzColW() + (n - 1);
});

// Compact time label for a chip, derived from start/end so it updates on drag.
const timeStr = (s: number, e: number) => `${fmtTime(s)}–${fmtTime(e)}`;

// Width left uncovered by chips on the right of each day column (timed grid and
// the all-day band), so you can always start a click/drag to create a new event
// even on a day/time that already has one.
const RIGHT_RESERVE = 20;

// Shared drag surface spanning all day columns (hosts the floating preview card
// and drop outline). All columns share the same width, so the per-column `w`
// passed to placeEvents doubles as the grid column width.
let dragLayer: Gtk.Fixed | null = null;

// ── Vimium-style event hints ────────────────────────────────────────────────
export const HINT_ALPHA = ["a", "s", "d", "f", "g", "h", "k", "l", ";"];
let hintFixed: Gtk.Fixed | null = null;
let alldayHintFixed: Gtk.Fixed | null = null;
let alldayColsBox: Gtk.Box | null = null;
let scrollAdj: Gtk.Adjustment | null = null;
let colsBox: Gtk.Box | null = null;
const hintMap = new Map<
  string,
  { ev: CalEvent; date: Date; label: Gtk.Widget }
>();
let hintBuffer = "";

// Equal-length hint labels (a, s, …, then aa, as, …) so none is a prefix.
function buildHints(n: number): string[] {
  if (n <= 0) return [];
  let len = 1;
  while (HINT_ALPHA.length ** len < n) len++;
  return Array.from({ length: n }, (_, i) => {
    let s = "";
    let x = i;
    for (let j = 0; j < len; j++) {
      s = HINT_ALPHA[x % HINT_ALPHA.length] + s;
      x = Math.floor(x / HINT_ALPHA.length);
    }
    return s;
  });
}

export function clearHints() {
  for (const f of [hintFixed, alldayHintFixed]) {
    if (!f) continue;
    clearChildren(f);
  }
  hintMap.clear();
  hintBuffer = "";
}

export function endHints() {
  clearHints();
  setHintMode(false);
}

// Label every event currently inside the scroll viewport, anchored to the
// bottom-right corner of each chip using its real rendered bounds.
export function startHints() {
  if (view.get() === "month" || !hintFixed || !scrollAdj || !colsBox) return;
  clearHints();
  const dates = view.get() === "day" ? [anchor.get()] : weekDays(anchor.get());
  const top = scrollAdj.get_value();
  const bottom = top + scrollAdj.get_page_size();
  const hidden = hiddenCals.get();

  // Each item is a chip widget + the Fixed its hint is placed on.
  const items: {
    ev: CalEvent;
    date: Date;
    widget: Gtk.Widget;
    fixed: Gtk.Fixed;
  }[] = [];

  // All-day chips (only when the band is expanded).
  if (allDayExpanded.get() && alldayHintFixed) {
    for (const date of dates) {
      for (const c of allDayOn(date).filter(
        (c) => !hidden.has(c.calendar ?? ""),
      )) {
        const w = chipReg.get(chipKey(c.id, date));
        if (w)
          items.push({
            ev: { ...c, start: 0, end: 0, allDay: true },
            date,
            widget: w,
            fixed: alldayHintFixed,
          });
      }
    }
  }

  // Timed chips inside the scroll viewport.
  for (const date of dates) {
    for (const ev of eventsOn(date).filter(
      (e) => !hidden.has(e.calendar ?? ""),
    )) {
      if (ev.end * HOUR_HEIGHT <= top || ev.start * HOUR_HEIGHT >= bottom)
        continue;
      const w = chipReg.get(chipKey(ev.id, date));
      if (w) items.push({ ev, date, widget: w, fixed: hintFixed });
    }
  }

  const hints = buildHints(items.length);
  items.forEach((it, i) => {
    const [ok, b] = it.widget.compute_bounds(it.fixed);
    if (!ok) return;
    const hint = hints[i];
    const label = (<label class="hint-label" label={hint} />) as Gtk.Widget;
    // Parent first so the CSS size (font/padding) is applied, then measure and
    // move into the exact bottom-right corner.
    it.fixed.put(label, 0, 0);
    const hw = label.measure(Gtk.Orientation.HORIZONTAL, -1)[1];
    const hh = label.measure(Gtk.Orientation.VERTICAL, -1)[1];
    it.fixed.move(
      label,
      Math.round(b.get_x() + b.get_width() - hw - 2),
      Math.round(b.get_y() + b.get_height() - hh - 2),
    );
    hintMap.set(hint, { ev: it.ev, date: it.date, label });
  });
  if (hintMap.size) setHintMode(true);
}

export function feedHintKey(ch: string) {
  hintBuffer += ch;
  const exact = hintMap.get(hintBuffer);
  if (exact) {
    pickEvent(exact.label, { ev: exact.ev, date: exact.date });
    endHints();
    return;
  }
  const keys = [...hintMap.keys()];
  if (!keys.some((k) => k.startsWith(hintBuffer))) return endHints();
  for (const [k, v] of hintMap)
    if (k.startsWith(hintBuffer)) v.label.remove_css_class("hint-dim");
    else v.label.add_css_class("hint-dim");
}

// Scroll the time grid (j/k).
export function scrollGrid(delta: number) {
  if (!scrollAdj) return;
  const max = Math.max(0, scrollAdj.get_upper() - scrollAdj.get_page_size());
  scrollAdj.set_value(
    Math.max(0, Math.min(scrollAdj.get_value() + delta, max)),
  );
}

// Let zoom keep the same hour in view: it reads the current offset before the
// rebuild and restores the scaled value after (on idle, once the taller/shorter
// content has been laid out and the adjustment's range updated).
registerZoomScroll(
  () => scrollAdj?.get_value() ?? 0,
  (v) => {
    const adj = scrollAdj;
    if (!adj) return;
    GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
      const max = Math.max(0, adj.get_upper() - adj.get_page_size());
      adj.set_value(Math.max(0, Math.min(v, max)));
      return GLib.SOURCE_REMOVE;
    });
  },
);

// Greedy overlap layout: assign each event a column + the cluster's column count
// so widths are dynamic (an event that no longer overlaps becomes full width).
function layoutDay(
  list: CalEvent[],
): { ev: CalEvent; col: number; cols: number }[] {
  const evs = list.slice().sort((a, b) => a.start - b.start || a.end - b.end);
  const out: { ev: CalEvent; col: number; cols: number }[] = [];
  let cluster: { ev: CalEvent; col: number; cols: number }[] = [];
  let colEnds: number[] = [];
  let clusterEnd = -1;
  const flush = () => {
    for (const r of cluster) r.cols = colEnds.length;
    out.push(...cluster);
    cluster = [];
    colEnds = [];
    clusterEnd = -1;
  };
  for (const ev of evs) {
    if (cluster.length && ev.start >= clusterEnd) flush();
    let col = colEnds.findIndex((end) => end <= ev.start);
    if (col === -1) {
      col = colEnds.length;
      colEnds.push(ev.end);
    } else colEnds[col] = ev.end;
    clusterEnd = Math.max(clusterEnd, ev.end);
    cluster.push({ ev, col, cols: 1 });
  }
  flush();
  return out;
}

// The stationary, clickable event chip. Returns its time label too, so resizing
// can update it live.
function eventChip(ev: CalEvent, date: Date) {
  const cls = ["event", `ev-${eventColor(ev)}`, `bar-${calColor(ev.calendar)}`];
  if (ev.selected) cls.push("selected");
  if (ev.status && ev.status !== "accepted") cls.push(ev.status); // invited/maybe/declined
  let btn: Gtk.Button;
  let timeLabel: Gtk.Label;
  // Events shorter than an hour are too short to stack a title above a time
  // without overflowing the grid, so render the time inline after the title.
  const short = ev.end - ev.start < 1;
  const widget = (
    <button
      class={cls.join(" ")}
      $={(b: Gtk.Button) => (btn = b)}
      // A multi-day chip is a per-day clamped copy → open the real event. Keep the
      // CLICKED day as the selection date so the editor anchors to (and re-anchors
      // to) this segment; the editor reads the Start/End rows from the event's own
      // date/endDate, so the times stay correct regardless of which day is clicked.
      onClicked={() => pickEvent(btn, { ev: liveEvent(ev.id) ?? ev, date })}
    >
      <box
        orientation={
          short ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL
        }
        spacing={short ? 4 : 0}
        valign={Gtk.Align.START}
      >
        {isBirthday(ev.title) ? (
          <box spacing={3} halign={START}>
            <image
              iconName="gift-symbolic"
              pixelSize={iconPx(10)}
              valign={Gtk.Align.CENTER}
            />
            <label
              class="ev-title"
              label={ev.title}
              ellipsize={3}
              wrap={false}
            />
          </box>
        ) : (
          <label
            class="ev-title"
            label={ev.title}
            halign={START}
            hexpand={short}
            ellipsize={3}
            wrap={false}
          />
        )}
        <box spacing={3} halign={short ? Gtk.Align.END : START}>
          <label
            class="ev-time"
            $={(l: Gtk.Label) => (timeLabel = l)}
            label={timeStr(ev.start, ev.end)}
            ellipsize={3}
          />
          {isRecurringEvent(ev) ? (
            <image
              class="ev-recur"
              iconName="media-playlist-repeat-symbolic"
              pixelSize={iconPx(9)}
              valign={Gtk.Align.CENTER}
            />
          ) : (
            <box />
          )}
        </box>
      </box>
    </button>
  ) as Gtk.Widget;
  return { widget, timeLabel: timeLabel! };
}

// A non-interactive copy of a chip — the floating drag preview.
function floatCard(ev: CalEvent, w: number, h: number) {
  let timeLabel: Gtk.Label;
  const card = (
    <box
      class={`event ev-${eventColor(ev)} bar-${calColor(ev.calendar)} floating`}
      orientation={Gtk.Orientation.VERTICAL}
      canTarget={false}
    >
      {isBirthday(ev.title) ? (
        <box spacing={3} halign={START}>
          <image
            iconName="gift-symbolic"
            pixelSize={iconPx(10)}
            valign={Gtk.Align.CENTER}
          />
          <label class="ev-title" label={ev.title} ellipsize={3} />
        </box>
      ) : (
        <label class="ev-title" label={ev.title} halign={START} ellipsize={3} />
      )}
      <label
        class="ev-time"
        $={(l: Gtk.Label) => (timeLabel = l)}
        label={timeStr(ev.start, ev.end)}
        halign={START}
        ellipsize={3}
      />
    </box>
  ) as Gtk.Widget;
  card.set_size_request(w, h);
  return { card, setTime: (t: string) => timeLabel!.set_label(t) };
}

// Synthesize busy-preview pseudo-events for `date` from the currently-previewed
// attendees (draft invitees minus toggled-off, plus saved attendees toggled on),
// each tinted by personColor. Returned as CalEvents flagged `busy` so they flow
// through the normal column layout but render as read-only blocks.
function busyPreviewEvents(date: Date): CalEvent[] {
  const off = invitePreviewOff.get();
  const drafts = draftInvites.get();
  const previewed: string[] = drafts.filter((email) => !off.has(email));
  for (const email of savedPreview.get())
    if (!drafts.includes(email)) previewed.push(email);
  if (!previewed.length) return [];

  const cache = freeBusy.get();
  const pad = (n: number) => String(n).padStart(2, "0");
  const dateStr = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const out: CalEvent[] = [];
  for (const email of previewed) {
    const color = personColor(email);
    const slots = googleConfigured()
      ? (cache.get(email) ?? []).filter((b) => b.date === dateStr)
      : personBusy(email, date);
    slots.forEach((b, i) => {
      out.push({
        id: `busy|${email}|${i}`,
        title: "Busy",
        start: b.start,
        end: b.end,
        color,
        busy: true,
      });
    });
  }
  return out;
}

// Lays a date's events into its Fixed at column position `colPos`, with dynamic
// overlap widths and a floating/outline drag that can cross days.
function placeEvents(fixed: Gtk.Fixed, date: Date, w: number, colPos: number) {
  clearChildren(fixed);
  if (w <= 0) return;

  const hidden = hiddenCals.get();
  const SNAP = HOUR_HEIGHT / 4;

  const events = eventsOn(date).filter((e) => !hidden.has(e.calendar ?? ""));
  // Busy-preview pseudo-events: draft invitees (shown by default) plus saved
  // attendees toggled on. Folded into the same layout so they pack side-by-side
  // with real events (and each other). Each person gets a distinct color.
  const busyEvents = busyPreviewEvents(date);

  for (const { ev, col, cols } of layoutDay([...events, ...busyEvents])) {
    const subW = (w - 2 - RIGHT_RESERVE) / cols;
    const x = 2 + col * subW;
    const width = Math.max(10, Math.floor(subW) - 2);
    const y = Math.round(ev.start * HOUR_HEIGHT);
    const dur = ev.end - ev.start;
    const h = Math.max(18, Math.round(dur * HOUR_HEIGHT) - 2);

    // Busy preview: a non-interactive hatched block in the person's color. No
    // chip registry / resize / drag — it's a read-only scheduling overlay.
    if (ev.busy) {
      const block = (
        <box class={`busy-block ev-${ev.color}`} canTarget={false}>
          <label
            class="busy-label"
            label="Busy"
            halign={START}
            valign={START}
          />
        </box>
      ) as Gtk.Widget;
      block.set_size_request(width, h);
      fixed.put(block, x, y);
      continue;
    }
    // True (gap-free) pixel span for resize math. `y`/`h` carry a 2px cosmetic
    // gap and an 18px minimum; ~2px is ~2 minutes, so using them for the times
    // would shave the resized edge (a 2pm end persisting as 1:58pm).
    const topPx = ev.start * HOUR_HEIGHT;
    const botPx = ev.end * HOUR_HEIGHT;
    const { widget, timeLabel } = eventChip(ev, date);
    widget.set_size_request(width, h);
    if (ev.id && ev.id === flashId.get()) widget.add_css_class("flash");
    chipReg.set(chipKey(ev.id, date), widget);
    fixed.put(widget, x, y);

    // Multi-day: hovering one day's segment highlights all of them.
    if (ev.endDate) {
      const m = new Gtk.EventControllerMotion();
      m.connect("enter", () => setSpanHover(ev.id, true));
      m.connect("leave", () => setSpanHover(ev.id, false));
      widget.add_controller(m);
    }

    // Edge resize handles: invisible hit strips at top/bottom that grow/shrink
    // the event from that end. The card resizes live; the handle stays put (so
    // the gesture offset is stable). Persists on release.
    const mkHandle = (edge: "top" | "bottom") => {
      const handle = (<box class="resize-handle" />) as Gtk.Widget;
      handle.set_size_request(width, 6);
      handle.set_cursor_from_name("ns-resize");
      fixed.put(handle, x, edge === "top" ? y - 3 : y + h - 3);
      let liveTop = topPx;
      let liveBot = botPx;
      const g = new Gtk.GestureDrag();
      g.connect(
        "drag-update",
        (gg: Gtk.GestureDrag, _ox: number, oy: number) => {
          if (Math.abs(oy) < 3) return;
          gg.set_state(Gtk.EventSequenceState.CLAIMED);
          if (edge === "top")
            liveTop = Math.max(
              0,
              Math.min(Math.round((topPx + oy) / SNAP) * SNAP, botPx - SNAP),
            );
          else
            liveBot = Math.max(
              liveTop + SNAP,
              Math.round((botPx + oy) / SNAP) * SNAP,
            );
          widget.set_size_request(width, Math.max(18, liveBot - liveTop - 2));
          fixed.move(widget, x, Math.round(liveTop));
          timeLabel.set_label(
            timeStr(liveTop / HOUR_HEIGHT, liveBot / HOUR_HEIGHT),
          );
        },
      );
      g.connect("drag-end", () => {
        setEventTime(ev.id, liveTop / HOUR_HEIGHT, liveBot / HOUR_HEIGHT);
      });
      handle.add_controller(g);
    };
    // Resize/drag only for single-day dated events — a recurring event is one
    // shared object rendered on every matching day, and a multi-day event's chips
    // are per-day clamped copies (resizing one would corrupt the real times).
    if (ev.date && !ev.endDate) {
      mkHandle("top");
      mkHandle("bottom");
    }

    // 2D drag: original stays put (dimmed); a floating card follows the cursor
    // on the shared drag layer; an outline previews the snapped slot. Gesture
    // stays on the stationary widget so offsets are stable (no flicker).
    const gridX = colPos * w + x;
    let floating: Gtk.Widget | null = null;
    let outline: Gtk.Widget | null = null;
    let setTime: ((t: string) => void) | null = null;
    let dropIdx = colPos;
    let dropY = y;
    const drag = new Gtk.GestureDrag();
    drag.connect(
      "drag-update",
      (g: Gtk.GestureDrag, ox: number, oy: number) => {
        if (!floating && Math.hypot(ox, oy) < 5) return;
        g.set_state(Gtk.EventSequenceState.CLAIMED);
        if (!dragLayer) return;
        const nDays = view.get() === "day" ? 1 : 7;
        if (!floating) {
          widget.add_css_class("ghost");
          const fc = floatCard(ev, width, h);
          floating = fc.card;
          setTime = fc.setTime;
          outline = (
            <box
              class={`drag-outline oc-${calColor(ev.calendar)}`}
              canTarget={false}
            />
          ) as Gtk.Widget;
          outline.set_size_request(width, h);
          dragLayer.put(outline, gridX, y);
          dragLayer.put(floating, gridX, y);
        }
        dragLayer.move(floating, gridX + ox, y + oy);
        dropIdx = Math.max(
          0,
          Math.min(nDays - 1, Math.round((gridX + ox) / w)),
        );
        const ny = Math.max(0, Math.min(y + oy, HOURS * HOUR_HEIGHT - h));
        dropY = Math.round(ny / SNAP) * SNAP;
        dragLayer.move(outline!, dropIdx * w + 2, dropY);
        const s = dropY / HOUR_HEIGHT;
        setTime!(timeStr(s, s + dur));
      },
    );
    drag.connect("drag-end", () => {
      if (!floating || !dragLayer) return;
      dragLayer.remove(floating);
      dragLayer.remove(outline!);
      widget.remove_css_class("ghost");
      const newStart = dropY / HOUR_HEIGHT;
      if (ev.date) {
        const target = addDays(startOfWeek(date), dropIdx);
        setEventMove(ev.id, target, newStart, newStart + dur);
      } else {
        setEventTime(ev.id, newStart, newStart + dur); // recurring: time only
      }
    });
    if (ev.date && !ev.endDate) widget.add_controller(drag);
  }
}

// Flexible day column: DrawingArea (CSS hour-line gradient + width reporter) as
// the overlay's main child, with a Gtk.Fixed of events stacked on top.
function DayColumn(date: Date) {
  let fixed: Gtk.Fixed | null = null;
  let lastW = 0;
  let dispose: (() => void) | null = null;
  // Column position within the displayed days (Sun-based in week view).
  const colPos = view.get() === "day" ? 0 : date.getDay();
  // Each relayout builds interactive (event-handler-bearing) widgets, so wrap it
  // in a reactive root and dispose the previous batch to avoid leaks/warnings.
  const relayout = () => {
    if (!fixed || lastW <= 0) return;
    if (dispose) dispose();
    createRoot((d) => {
      dispose = d;
      placeEvents(fixed!, date, lastW, colPos);
    });
  };
  // Re-lay-out in place when the draft-invite busy preview changes, instead of
  // letting `days` recompute and tear the whole grid down (which would dismiss
  // an open floating event editor mid-interaction).
  const unsubs = [
    draftInvites.subscribe(relayout),
    freeBusy.subscribe(relayout),
    freeBusyLoading.subscribe(relayout),
    flashId.subscribe(relayout),
    invitePreviewOff.subscribe(relayout),
    savedPreview.subscribe(relayout),
  ];
  onCleanup(() => unsubs.forEach((u) => u()));
  return (
    <overlay class="day-col-wrap" hexpand>
      <Gtk.DrawingArea
        class="day-col"
        hexpand
        widthRequest={36}
        heightRequest={HOURS * HOUR_HEIGHT}
        $={(area: Gtk.DrawingArea) =>
          area.connect("resize", (_a: Gtk.DrawingArea, w: number) => {
            lastW = w;
            relayout();
          })
        }
      />
      <Gtk.Fixed
        $type="overlay"
        $={(ref: Gtk.Fixed) => {
          fixed = ref;
          relayout();

          // Drag on empty space to create an event. The Fixed covers the column,
          // so the gesture lives here; pick() tells us if we started on empty
          // space (not on an event chip or resize handle).
          const SNAP = HOUR_HEIGHT / 4;
          let startY = 0;
          let onEmpty = false;
          let preview: Gtk.Widget | null = null;
          let range: [number, number] = [0, 0];
          const cd = new Gtk.GestureDrag();
          cd.connect("drag-begin", (_g, sx: number, sy: number) => {
            startY = sy;
            const hit = ref.pick(sx, sy, Gtk.PickFlags.DEFAULT);
            onEmpty = !hit || hit === ref;
          });
          cd.connect("drag-update", (g: Gtk.GestureDrag, _ox, oy: number) => {
            if (!onEmpty) return;
            if (!preview && Math.abs(oy) < 6) return;
            g.set_state(Gtk.EventSequenceState.CLAIMED);
            const a = Math.round(Math.min(startY, startY + oy) / SNAP) * SNAP;
            const b = Math.round(Math.max(startY, startY + oy) / SNAP) * SNAP;
            if (!preview) {
              preview = (
                <box class="create-preview" canTarget={false} />
              ) as Gtk.Widget;
              ref.put(preview, 2, a);
            }
            preview.set_size_request(lastW - 4, Math.max(SNAP, b - a));
            ref.move(preview, 2, a);
            range = [a / HOUR_HEIGHT, b / HOUR_HEIGHT];
          });
          cd.connect("drag-end", () => {
            if (!preview) return;
            ref.remove(preview);
            preview = null;
            const [s, e] = range;
            if (e - s < 0.2) return;
            const ev = createEvent({
              title: "New event",
              start: s,
              end: e,
              date,
              calendar: defaultCal.get(),
            });
            setSelected({ ev, date, isNew: true });
          });
          ref.add_controller(cd);

          // Plain click on empty space: create a default 1-hour event at the
          // clicked (snapped) time. A real drag claims the sequence above, so
          // this only fires for taps — no double-create.
          const ck = new Gtk.GestureClick();
          ck.connect("released", (_g, _n: number, x: number, y: number) => {
            const hit = ref.pick(x, y, Gtk.PickFlags.DEFAULT);
            if (hit && hit !== ref) return; // clicked a chip / resize handle
            const s = (Math.round(y / SNAP) * SNAP) / HOUR_HEIGHT;
            const e = Math.min(s + 1, 24);
            if (e <= s) return;
            const ev = createEvent({
              title: "New event",
              start: s,
              end: e,
              date,
              calendar: defaultCal.get(),
            });
            setSelected({ ev, date, isNew: true });
          });
          ref.add_controller(ck);
        }}
      />
    </overlay>
  );
}

function DayHeader(date: Date) {
  const today = sameDay(date, TODAY);
  return (
    <box class={`day-head${today ? " today" : ""}`} hexpand spacing={6}>
      {/* Click the day header to add an all-day event — a reliable target now
          that the all-day chips fill the column (no right-margin strip left). */}
      <Gtk.GestureClick onReleased={() => createAllDay(date)} />
      <label class="dh-dow" label={fmtDow(date)} />
      <label
        class={`dh-date${today ? " pill" : ""}`}
        label={`${date.getDate()}`}
      />
    </box>
  );
}

// Create a new all-day event on `date` and open it.
function createAllDay(date: Date) {
  const ev = createEvent({
    title: "New event",
    start: 0,
    end: 0,
    date,
    calendar: defaultCal.get(),
  });
  setAllDay(ev.id, true);
  setSelected({ ev, date, isNew: true });
}

function AllDayCell(date: Date) {
  const hidden = hiddenCals.get();
  const chips = allDayOn(date).filter((c) => !hidden.has(c.calendar ?? ""));
  let cell: Gtk.Box;
  return (
    <box
      class="allday-cell"
      hexpand
      orientation={Gtk.Orientation.VERTICAL}
      spacing={2}
      $={(b: Gtk.Box) => (cell = b)}
    >
      {/* Click empty space to add an all-day event. Chip buttons claim their own
          clicks, so this only fires on the empty part of the cell. */}
      <Gtk.GestureClick
        onReleased={(_g, _n, x: number, y: number) => {
          let w = cell.pick(x, y, Gtk.PickFlags.DEFAULT) as Gtk.Widget | null;
          while (w && w !== cell) {
            if (w instanceof Gtk.Button) return; // clicked a chip
            w = w.get_parent();
          }
          createAllDay(date);
        }}
      />
      {/* expanded: full chips */}
      <box
        orientation={Gtk.Orientation.VERTICAL}
        spacing={2}
        visible={allDayExpanded((e) => e)}
      >
        {chips.map((c) => {
          let btn: Gtk.Button;
          const part = spanPart(c, date);
          // Shared all-day→CalEvent shape (carries links/recurringEventId, which
          // a hand-rolled literal had been dropping).
          const ev = allDayAsCalEvent(c);
          return (
            <button
              class={`allday ev-${eventColor(c)} bar-${calColor(c.calendar)}${
                part !== "single" ? ` span-${part}` : ""
              }`}
              widthRequest={1}
              hexpand
              $={(b: Gtk.Button) => {
                btn = b;
                chipReg.set(chipKey(c.id, date), b);
                // Multi-day: hovering one segment highlights all of them.
                if (part !== "single") {
                  const m = new Gtk.EventControllerMotion();
                  m.connect("enter", () => setSpanHover(c.id, true));
                  m.connect("leave", () => setSpanHover(c.id, false));
                  b.add_controller(m);
                }
              }}
              onClicked={() =>
                pickEvent(
                  btn,
                  { ev, date },
                  part !== "single" ? spanWidgets(c.id) : undefined,
                )
              }
            >
              <box spacing={3}>
                {/* Continuation days of a multi-day span show just the bar — an
                    empty label (not a box) so it still reserves the chip's line
                    height instead of collapsing to a sliver. */}
                {part === "mid" || part === "end" ? (
                  <label label="" hexpand />
                ) : isBirthday(c.title) ? (
                  <box spacing={3} halign={START} hexpand>
                    <image
                      iconName="gift-symbolic"
                      pixelSize={iconPx(10)}
                      valign={Gtk.Align.CENTER}
                    />
                    <label label={c.title} ellipsize={3} xalign={0} hexpand />
                  </box>
                ) : (
                  <label
                    label={c.title}
                    ellipsize={3}
                    xalign={0}
                    halign={START}
                    hexpand
                  />
                )}
                {isRecurringEvent(c) &&
                (part === "start" || part === "single") ? (
                  <image
                    class="ev-recur"
                    iconName="media-playlist-repeat-symbolic"
                    pixelSize={iconPx(9)}
                    valign={Gtk.Align.CENTER}
                  />
                ) : (
                  <box />
                )}
              </box>
            </button>
          );
        })}
      </box>
      {/* collapsed: "N events" summary */}
      <label
        class="allday-count"
        label={`${chips.length} event${chips.length === 1 ? "" : "s"}`}
        visible={allDayExpanded((e) => !e && chips.length > 0)}
      />
    </box>
  );
}

// One timezone gutter column: hour labels positioned on the lines via a Fixed,
// including one extra label at the very bottom (the hour after the last line)
// without adding height. First label is nudged down, the last nudged up, so
// neither clips at the grid edges.
function TzColumn(offset: number, last: boolean) {
  const w = tzColW.get();
  return (
    <box
      class={`tz-col${last ? " last" : ""}`}
      widthRequest={w}
      hexpand={false}
    >
      <Gtk.Fixed
        hexpand
        heightRequest={HOURS * HOUR_HEIGHT}
        $={(f: Gtk.Fixed) => {
          for (let h = 0; h <= HOURS; h++) {
            const lbl = (
              <label
                class="hour-label"
                label={fmtHour(h + offset)}
                xalign={1}
              />
            ) as Gtk.Widget;
            lbl.set_size_request(w - 6, -1); // 6px right gap
            let y = h * HOUR_HEIGHT - 7;
            if (h === 0)
              y = 3; // pull the first label down
            else if (h === HOURS) y = HOURS * HOUR_HEIGHT - 14; // pull last up
            f.put(lbl, 0, y);
          }
        }}
      />
    </box>
  );
}

// One timezone header cell. The default (index 0) is a plain, non-clickable
// label; the rest are menubuttons offering "Make default" / "Remove".
function TzHeader(item: { tz: { label: string }; i: number; last: boolean }) {
  const { tz, i, last } = item;
  const edge = last ? " last" : "";
  if (i === 0)
    return (
      <label
        class={`tz-label default tz-cell${edge}`}
        label={tz.label}
        widthRequest={tzColW((w) => w)}
        valign={Gtk.Align.END}
      />
    );
  let pop: Gtk.Popover;
  return (
    <menubutton
      class={`tz-label tz-cell${edge}`}
      tooltipText="Timezone options"
      widthRequest={tzColW((w) => w)}
      valign={Gtk.Align.END}
    >
      <label label={tz.label} />
      <popover class="tz-pop" $={(p: Gtk.Popover) => (pop = p)}>
        <box class="tz-menu" orientation={Gtk.Orientation.VERTICAL}>
          <button
            class="tz-item"
            onClicked={() => {
              makeDefaultTimezone(i);
              pop.popdown();
            }}
          >
            <label label="Make default" halign={START} />
          </button>
          <button
            class="tz-item"
            onClicked={() => {
              removeTimezone(i);
              pop.popdown();
            }}
          >
            <label label="Remove" halign={START} />
          </button>
        </box>
      </popover>
    </menubutton>
  );
}

// "+" button: search the catalog and add a timezone to the gutter.
function AddTzButton() {
  let pop: Gtk.Popover;
  let listBox: Gtk.Box;
  let search: Gtk.Entry;
  let dispose: (() => void) | null = null;
  const renderList = (q: string) => {
    clearChildren(listBox);
    // The rows are built imperatively; wrap in a root so their cleanup has a
    // tracking context (otherwise gnim warns "out of tracking context").
    if (dispose) dispose();
    createRoot((d) => {
      dispose = d;
      const ql = q.toLowerCase().trim();
      const items = (
        ql
          ? TIMEZONES.filter(
              (s) =>
                s.title.toLowerCase().includes(ql) ||
                s.subtitle.toLowerCase().includes(ql),
            )
          : TIMEZONES
      ).slice(0, 200);
      for (const s of items)
        listBox.append(
          (
            <button
              class="tz-item"
              onClicked={() => {
                addTimezone(tzFromZone(s.title, s.subtitle));
                pop.popdown();
              }}
            >
              {Row(s, ql, false)}
            </button>
          ) as Gtk.Widget,
        );
    });
  };
  return (
    <menubutton class="add-tz" tooltipText="Add timezone" valign={START}>
      <image iconName="list-add-symbolic" pixelSize={iconPx(12)} />
      <popover
        class="tz-pop"
        $={(p: Gtk.Popover) => {
          pop = p;
          // Reset + focus the search each time it opens.
          p.connect("map", () => {
            search.set_text("");
            renderList("");
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
              search.grab_focus();
              return GLib.SOURCE_REMOVE;
            });
          });
        }}
      >
        <box class="tz-add" orientation={Gtk.Orientation.VERTICAL} spacing={6}>
          <entry
            class="tz-search"
            $={(e: Gtk.Entry) => (search = e)}
            primaryIconName="system-search-symbolic"
            placeholderText="Search timezones"
            onNotifyText={({ text }: Gtk.Entry) => renderList(text)}
          />
          <scrolledwindow
            class="tz-add-scroll"
            maxContentHeight={320}
            propagateNaturalHeight
            hscrollbarPolicy={Gtk.PolicyType.NEVER}
          >
            <box
              class="tz-menu"
              orientation={Gtk.Orientation.VERTICAL}
              $={(b: Gtk.Box) => {
                listBox = b;
                renderList("");
              }}
            />
          </scrolledwindow>
        </box>
      </popover>
    </menubutton>
  );
}

export default function WeekView() {
  let viewPop: Gtk.Popover;
  // Photo and ring color for the account that owns the default calendar.
  const avatarPhoto = createComputed(() => {
    const cal = defaultCal();
    const acct = accounts().find((a) =>
      a.calendars.some((c) => c.name === cal),
    );
    return acct?.photo ?? null;
  });
  const avatarClass = createComputed(
    () => `avatar ring-${calColor(defaultCal())}`,
  );
  // Week view shows the 7 days around the anchor; day view shows just it.
  // Reading hiddenCals() makes the columns rebuild when a calendar is toggled.
  const days = createComputed(() => {
    hiddenCals();
    zoom(); // rebuild columns (HOUR_HEIGHT changed) on zoom
    rev(); // rebuild columns when an event's color/calendar changes
    // The columns (and their chips) are about to be rebuilt, so drop the stale
    // hint registry — otherwise it grows one entry per event×date navigated.
    chipReg.clear();
    // Draft-invite busy preview is handled per-column (DayColumn subscribes to
    // draftInvites/invitePreviewOff) so adding an invitee doesn't tear down the
    // grid and dismiss an open floating editor.
    // Fresh Date each run so <For> (keyed by item identity) re-renders the
    // column on rev bumps — otherwise new events wouldn't appear in day view.
    return view() === "day" ? [new Date(anchor())] : weekDays(anchor());
  });

  // Refresh freebusy whenever invitees, the visible week, or connected accounts change.
  const triggerFreeBusy = () => void refreshFreeBusy(anchor.get());
  const fbUnsubs = [
    draftInvites.subscribe(triggerFreeBusy),
    savedPreview.subscribe(triggerFreeBusy),
    anchor.subscribe(triggerFreeBusy),
    accounts.subscribe(triggerFreeBusy),
  ];
  onCleanup(() => fbUnsubs.forEach((u) => u()));

  function pick(v: "week" | "day" | "month") {
    setView(v);
    viewPop.popdown();
  }

  // ‹ › step by a day / week / month depending on the active view.
  function step(dir: number) {
    const v = view();
    setAnchor((a) =>
      v === "month"
        ? addMonths(a, dir)
        : addDays(a, dir * (v === "day" ? 1 : 7)),
    );
  }

  const label = (v: string) =>
    v === "day" ? "Day" : v === "month" ? "Month" : "Week";

  return (
    <box class="week" orientation={Gtk.Orientation.VERTICAL} hexpand>
      {/* Top bar: month title + view controls */}
      <box class="topbar" spacing={8}>
        {/* reveal left sidebar when collapsed */}
        <button
          class="icon-btn"
          tooltipText="Show sidebar"
          visible={leftVisible((v) => !v)}
          onClicked={() => {
            setLeftVisible(true);
            // This button just unmapped; hand focus to the in-sidebar collapse
            // button (now visible) so it stays on the toggle instead of falling
            // through to the timezone "+". Deferred so the target is mapped first.
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
              sidebarToggle.left.collapse?.();
              return GLib.SOURCE_REMOVE;
            });
          }}
          $={(b: Gtk.Button) =>
            (sidebarToggle.left.expand = () => b.grab_focus())
          }
        >
          <image iconName="sidebar-show-symbolic" pixelSize={iconPx(15)} />
        </button>
        <label
          class="month-title"
          label={anchor((a) => fmtMonthYear(a))}
          halign={START}
          hexpand
        />
        <image
          class={avatarClass((c) => c)}
          file={avatarPhoto((p) => p ?? "")}
          pixelSize={iconPx(28)}
          valign={Gtk.Align.CENTER}
          visible={avatarPhoto((p) => p !== null)}
        />
        <box
          class={avatarClass((c) => c)}
          valign={Gtk.Align.CENTER}
          visible={avatarPhoto((p) => p === null)}
        />
        <menubutton class="pill-btn" tooltipText="Change view (D / W / M)">
          <box spacing={6}>
            <label label={view(label)} />
            <image iconName="pan-down-symbolic" pixelSize={iconPx(12)} />
          </box>
          <popover $={(p: Gtk.Popover) => (viewPop = p)}>
            <box class="view-menu" orientation={Gtk.Orientation.VERTICAL}>
              <button onClicked={() => pick("day")}>
                <label label="Day" xalign={0} />
              </button>
              <button onClicked={() => pick("week")}>
                <label label="Week" xalign={0} />
              </button>
              <button onClicked={() => pick("month")}>
                <label label="Month" xalign={0} />
              </button>
            </box>
          </popover>
        </menubutton>
        <button
          class="pill-btn"
          tooltipText="Go to today (T)"
          onClicked={() => setAnchor(TODAY)}
        >
          <label label="Today" />
        </button>
        <button
          class="icon-btn"
          tooltipText="Previous (←)"
          onClicked={() => step(-1)}
        >
          <image iconName="pan-start-symbolic" pixelSize={iconPx(14)} />
        </button>
        <button
          class="icon-btn"
          tooltipText="Next (→)"
          onClicked={() => step(1)}
        >
          <image iconName="pan-end-symbolic" pixelSize={iconPx(14)} />
        </button>
        {/* reveal right sidebar when collapsed */}
        <button
          class="icon-btn"
          tooltipText="Show details panel"
          visible={rightVisible((v) => !v)}
          onClicked={() => {
            setRightVisible(true);
            // With an event selected the details pane rebuilds and focuses the
            // title, so only keep focus on the toggle when nothing's selected.
            if (selected.get()) return;
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
              sidebarToggle.right.collapse?.();
              return GLib.SOURCE_REMOVE;
            });
          }}
          $={(b: Gtk.Button) =>
            (sidebarToggle.right.expand = () => b.grab_focus())
          }
        >
          <image
            iconName="sidebar-show-right-symbolic"
            pixelSize={iconPx(15)}
          />
        </button>
      </box>

      {/* Week / Day time grid */}
      <box
        class="week-body"
        orientation={Gtk.Orientation.VERTICAL}
        vexpand
        visible={view((v) => v !== "month")}
      >
        {/* Day-of-week header row (pinned above the scroll) */}
        <box class="header-row">
          {/* Overlay the + on the gutter's empty top-left so it adds no height
              and the tz labels stay bottom-aligned with the day headers. */}
          <box class="gutter tz-head" widthRequest={gutterW((w) => w)}>
            <overlay>
              <box class="tz-head-labels" valign={Gtk.Align.END}>
                <For each={tzList}>{(item) => TzHeader(item)}</For>
              </box>
              <box
                class="tz-head-top"
                $type="overlay"
                halign={START}
                valign={START}
                widthRequest={tzColW((w) => w)}
              >
                <box hexpand />
                <AddTzButton />
                <box hexpand />
              </box>
            </overlay>
          </box>
          <box class="cols" homogeneous hexpand>
            <For each={days}>{(d: Date) => DayHeader(d)}</For>
          </box>
        </box>

        {/* All-day band */}
        <box class={allDayExpanded((e) => `allday-row${e ? " expanded" : ""}`)}>
          {/* Spacer cells mirror the grid tz-columns so the gutter is exactly
              as wide as the time-axis; the toggle sits in the second column. */}
          <box class="gutter" widthRequest={gutterW((w) => w)} hexpand={false}>
            <For each={tzList}>
              {(item) => (
                <box
                  class={`tz-cell${item.last ? " last" : ""}`}
                  widthRequest={tzColW((w) => w)}
                >
                  <box hexpand />
                  {item.caret ? (
                    <button
                      class="allday-toggle"
                      valign={START}
                      tooltipText={allDayExpanded((e) =>
                        e ? "Collapse all-day events" : "Expand all-day events",
                      )}
                      onClicked={() => setAllDayExpanded((e) => !e)}
                    >
                      <image
                        iconName={allDayExpanded((e) =>
                          e ? "pan-down-symbolic" : "pan-up-symbolic",
                        )}
                        pixelSize={iconPx(12)}
                      />
                    </button>
                  ) : (
                    <box />
                  )}
                </box>
              )}
            </For>
          </box>
          <overlay hexpand>
            <box
              class="cols"
              homogeneous
              hexpand
              $={(b: Gtk.Box) => (alldayColsBox = b)}
            >
              <For each={days}>{(d: Date) => AllDayCell(d)}</For>
            </box>
            <Gtk.Fixed
              class="hint-layer"
              $type="overlay"
              canTarget={false}
              $={(f: Gtk.Fixed) => (alldayHintFixed = f)}
            />
          </overlay>
        </box>

        {/* Scrollable time grid */}
        <scrolledwindow
          class="grid-scroll"
          vexpand
          hscrollbarPolicy={Gtk.PolicyType.NEVER}
          $={(sw: Gtk.ScrolledWindow) => {
            // Center the now-line once layout has settled (page_size/upper are 0
            // until the grid is allocated; setting too early gets reset).
            const adj = sw.get_vadjustment();
            scrollAdj = adj; // shared with j/k scroll + event hints
            const center = () => {
              const ps = adj.get_page_size();
              const up = adj.get_upper();
              if (ps <= 0 || up <= 0) return false; // not laid out yet — retry
              const max = Math.max(0, up - ps);
              const target = NOW_HOUR * HOUR_HEIGHT - ps / 2;
              adj.set_value(Math.max(0, Math.min(target, max)));
              return true;
            };
            let tries = 0;
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, () =>
              center() || ++tries > 20
                ? GLib.SOURCE_REMOVE
                : GLib.SOURCE_CONTINUE,
            );
          }}
        >
          <overlay>
            <box class="grid">
              <box
                class="time-axis"
                widthRequest={gutterW((w) => w)}
                hexpand={false}
              >
                <For each={tzList}>
                  {(item) => TzColumn(item.rel, item.last)}
                </For>
              </box>
              {/* Overlay a transparent drag layer across all day columns so a
                  dragged event can float and cross days. */}
              <overlay hexpand>
                <box
                  class="cols"
                  homogeneous
                  hexpand
                  $={(b: Gtk.Box) => (colsBox = b)}
                >
                  <For each={days}>{(d: Date) => DayColumn(d)}</For>
                </box>
                <Gtk.Fixed
                  class="drag-layer"
                  $type="overlay"
                  canTarget={false}
                  $={(f: Gtk.Fixed) => (dragLayer = f)}
                />
                <Gtk.Fixed
                  class="hint-layer"
                  $type="overlay"
                  canTarget={false}
                  $={(f: Gtk.Fixed) => (hintFixed = f)}
                />
              </overlay>
            </box>
            {/* Now-line spanning every day column, with the time pill at the far
                left of the gutter. */}
            {/* Spans the full width including the timezone gutter; the pill
                overlays its left end. */}
            <box
              class="now-line"
              $type="overlay"
              valign={START}
              hexpand
              heightRequest={2}
              canTarget={false}
              marginTop={nowHour((h) => Math.round(h * HOUR_HEIGHT))}
            />
            <label
              class="now-pill"
              $type="overlay"
              valign={START}
              halign={START}
              canTarget={false}
              marginTop={nowHour((h) =>
                Math.max(0, Math.round(h * HOUR_HEIGHT) - 8),
              )}
              label={nowHour((h) => fmtTime(h))}
            />
          </overlay>
        </scrolledwindow>
      </box>

      {/* Month grid */}
      <box vexpand visible={view((v) => v === "month")}>
        <MonthView />
      </box>
    </box>
  );
}
