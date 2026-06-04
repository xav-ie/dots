import { createRoot } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import GLib from "gi://GLib";
import {
  ALL_DAY,
  EVENTS,
  allDayAsCalEvent,
  eventColor,
  isBirthday,
  isRecurringEvent,
  type CalEvent,
} from "./data";
import { fmtFullDate, fmtTime } from "./datetime";
import {
  anchor,
  rightVisible,
  search,
  selected,
  setAnchor,
  setFlashId,
  setRightVisible,
  setSearch,
  setSelected,
  sidebarToggle,
} from "./state";
import EventInfo from "./EventInfo";
import { googleConfigured, searchGoogle } from "./gmap";
import { PANEL_SHORTCUTS } from "./shortcuts";

const START = Gtk.Align.START;
// Guards the async remote search: a newer query bumps the generation so a stale
// in-flight result is ignored, and the pending debounce timer is cancelled.
let searchGen = 0;
let searchTimer: number | null = null;
// Disposes the previous result rows' reactive bindings (iconPx scales with zoom);
// fillResults builds rows imperatively, so each batch needs its own root.
let fillDispose: (() => void) | null = null;

function Shortcuts() {
  return (
    <box class="shortcuts" orientation={Gtk.Orientation.VERTICAL} spacing={9}>
      <label class="shortcuts-title" label="Useful shortcuts" halign={START} />
      {PANEL_SHORTCUTS.map(({ name, keys }) => (
        <box spacing={8}>
          <label class="shortcut-name" label={name} halign={START} hexpand />
          <box spacing={3}>
            {keys.map((k) => (
              <label class="kbd" label={k} />
            ))}
          </box>
        </box>
      ))}
    </box>
  ) as Gtk.Widget;
}

function ResultRow(ev: CalEvent, date: Date | null, onPick: () => void) {
  const range = ev.allDay
    ? "All day"
    : `${fmtTime(ev.start)}–${fmtTime(ev.end)}`;
  return (
    <button class={`result ev-${eventColor(ev)}`} onClicked={onPick}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <box spacing={4}>
          {isBirthday(ev.title) ? (
            <box spacing={4} halign={START} hexpand>
              <image
                iconName="gift-symbolic"
                pixelSize={iconPx(12)}
                valign={Gtk.Align.CENTER}
              />
              <label
                class="result-title"
                label={ev.title}
                ellipsize={3}
                hexpand
              />
            </box>
          ) : (
            <label
              class="result-title"
              label={ev.title}
              halign={START}
              ellipsize={3}
              hexpand
            />
          )}
          {isRecurringEvent(ev) ? (
            <image
              class="ev-recur"
              iconName="media-playlist-repeat-symbolic"
              pixelSize={iconPx(10)}
              valign={Gtk.Align.CENTER}
            />
          ) : (
            <box />
          )}
        </box>
        <label class="result-time muted" label={range} halign={START} />
      </box>
    </button>
  );
}

// (Re)fill a results box: events grouped by date (recurring seeds under
// "Weekly"), date-sorted. Empty → "Searching…" while a remote query is pending,
// else "No results".
function fillResults(
  box: Gtk.Box,
  evs: CalEvent[],
  onPick: (ev: CalEvent, date: Date | null) => void,
  pending: boolean,
) {
  clearChildren(box);
  if (fillDispose) {
    fillDispose();
    fillDispose = null;
  }
  if (evs.length === 0) {
    box.append(
      (
        <label
          class="muted no-results"
          label={pending ? "Searching…" : "No results"}
          halign={START}
        />
      ) as Gtk.Widget,
    );
    return;
  }
  // Proximity order (matches searchGoogle): upcoming days first (soonest), then
  // past days (most recent) — grouped by day, so the imminent event leads.
  const now = Date.now();
  const startMs = (e: CalEvent): number => {
    if (!e.date) return Infinity;
    const h = e.allDay || e.start == null ? 0 : e.start;
    return new Date(
      e.date[0],
      e.date[1],
      e.date[2],
      Math.floor(h),
      Math.round((h - Math.floor(h)) * 60),
    ).getTime();
  };
  const sorted = [...evs].sort((a, b) => {
    const sa = startMs(a);
    const sb = startMs(b);
    const fa = sa >= now;
    const fb = sb >= now;
    if (fa !== fb) return fa ? -1 : 1;
    return fa ? sa - sb : sb - sa;
  });
  const groups = new Map<string, { date: Date | null; evs: CalEvent[] }>();
  for (const e of sorted) {
    const d = e.date ? new Date(e.date[0], e.date[1], e.date[2]) : null;
    const key = d ? `${fmtFullDate(d)}, ${d.getFullYear()}` : "Weekly";
    if (!groups.has(key)) groups.set(key, { date: d, evs: [] });
    groups.get(key)!.evs.push(e);
  }
  createRoot((dispose) => {
    fillDispose = dispose;
    for (const [key, g] of groups) {
      box.append(
        (
          <label class="results-date" label={key} halign={START} />
        ) as Gtk.Widget,
      );
      for (const e of g.evs)
        box.append(ResultRow(e, g.date, () => onPick(e, g.date)) as Gtk.Widget);
    }
  });
}

function SearchResults(
  q: string,
  onPick: (ev: CalEvent, date: Date | null) => void,
) {
  const ql = q.toLowerCase();
  const local = [...EVENTS, ...ALL_DAY.map(allDayAsCalEvent)].filter((e) =>
    e.title.toLowerCase().includes(ql),
  );
  const box = (
    <box class="results" orientation={Gtk.Orientation.VERTICAL} spacing={4} />
  ) as Gtk.Box;
  const remoteOn = googleConfigured() && q.trim().length >= 2;
  fillResults(box, local, onPick, remoteOn && local.length === 0);

  // Debounced server-side search (covers all time + description/location/guests),
  // merged with the local hits and deduped by id. Falls back to local on failure.
  if (searchTimer) {
    GLib.source_remove(searchTimer);
    searchTimer = null;
  }
  if (remoteOn) {
    const gen = ++searchGen;
    searchTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
      searchTimer = null;
      void searchGoogle(q)
        .then((remote) => {
          if (gen !== searchGen) return;
          const seen = new Set<string>();
          const merged: CalEvent[] = [];
          for (const e of [...local, ...remote]) {
            if (e.id && seen.has(e.id)) continue;
            if (e.id) seen.add(e.id);
            merged.push(e);
          }
          fillResults(box, merged, onPick, false);
        })
        .catch(() => {
          if (gen === searchGen) fillResults(box, local, onPick, false);
        });
      return GLib.SOURCE_REMOVE;
    });
  }
  return box;
}

export default function EventDetails() {
  let bodyRef: Gtk.Box;
  let searchEntry: Gtk.Entry;
  let dispose: (() => void) | null = null;
  // Pick a search result: jump the grid to its day and open it; clear the search.
  function onPick(ev: CalEvent, date: Date | null) {
    const d = date ?? anchor.get();
    setAnchor(d);
    searchEntry.set_text("");
    setSearch("");
    setSelected({ ev, date: d });
    // Flash the chip in the grid, then clear so the animation can replay later.
    setFlashId(ev.id ?? null);
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1900, () => {
      setFlashId(null);
      return GLib.SOURCE_REMOVE;
    });
  }
  function render() {
    clearChildren(bodyRef);
    if (dispose) dispose();
    createRoot((d) => {
      dispose = d;
      const q = search.get().trim();
      const sel = selected.get();
      if (q) bodyRef.append(SearchResults(q, onPick));
      else if (sel) bodyRef.append(EventInfo(sel) as Gtk.Widget);
      else bodyRef.append(Shortcuts());
    });
  }

  return (
    <box
      class="sidebar right"
      orientation={Gtk.Orientation.VERTICAL}
      hexpand={false}
      widthRequest={iconPx(300)}
      visible={rightVisible((v) => v)}
    >
      <box class="side-top" spacing={6}>
        <entry
          class="search-box"
          hexpand
          $={(e: Gtk.Entry) => (searchEntry = e)}
          primaryIconName="system-search-symbolic"
          placeholderText="Search events"
          onNotifyText={({ text }: Gtk.Entry) => setSearch(text)}
        />
        <button
          class="icon-btn"
          tooltipText="Collapse panel"
          onClicked={() => {
            setRightVisible(false);
            // With an event selected the floating editor appears and focuses the
            // title, so only keep focus on the toggle when nothing's selected.
            if (selected.get()) return;
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
              sidebarToggle.right.expand?.();
              return GLib.SOURCE_REMOVE;
            });
          }}
          $={(b: Gtk.Button) =>
            (sidebarToggle.right.collapse = () => b.grab_focus())
          }
        >
          <image
            iconName="sidebar-show-right-symbolic"
            pixelSize={iconPx(15)}
          />
        </button>
      </box>

      <scrolledwindow
        vexpand
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
        $={(sw: Gtk.ScrolledWindow) => sw.set_propagate_natural_width(false)}
      >
        <box
          class="detail-body"
          orientation={Gtk.Orientation.VERTICAL}
          $={(ref: Gtk.Box) => {
            bodyRef = ref;
            render();
            selected.subscribe(render);
            search.subscribe(render);
            // Rebuild when the pane opens so the title re-focuses (the editor
            // was built while the pane was hidden).
            rightVisible.subscribe(() => rightVisible.get() && render());
          }}
        />
      </scrolledwindow>
    </box>
  );
}
