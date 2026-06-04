import { createRoot } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import GLib from "gi://GLib";
import Graphene from "gi://Graphene";
import { PEOPLE, type Suggestion } from "./data";
import { NOW_HOUR, TODAY } from "./datetime";
import { fetchContacts } from "./contacts";
import { googleConfigured } from "./gmap";
import { createEvent } from "./store";
import { modalFocusTrap } from "./focusTrap";
import {
  anchor,
  defaultCal,
  draftHolder,
  goToday,
  paletteIntent,
  paletteOpen,
  setAnchor,
  setDraftInvites,
  setPaletteIntent,
  setPaletteOpen,
  setSelected,
  stepAnchor,
} from "./state";

// Parse a typed date: ISO (2026-06-15) or loose ("Jun 15", "June 15 2026").
// A year-less value is assumed to be the current year.
function parseDate(s: string): Date | null {
  if (!s) return null;
  let d = new Date(s);
  if (isNaN(d.getTime())) d = new Date(`${s} ${TODAY.getFullYear()}`);
  return isNaN(d.getTime()) ? null : d;
}

const START = Gtk.Align.START;

interface Cmd {
  name: string;
  keys: string[];
  action?: () => void;
}

const CmdRow = (c: Cmd): Gtk.Widget =>
  (
    <button
      class="cmd-row"
      onClicked={c.action ?? (() => setPaletteOpen(false))}
    >
      <box spacing={10}>
        <label label={c.name} halign={START} hexpand />
        <box spacing={3}>
          {c.keys.map((k) => (
            <label class="kbd" label={k} />
          ))}
        </box>
      </box>
    </button>
  ) as Gtk.Widget;

const PersonRow = (
  p: { title: string; subtitle: string },
  onSelect: () => void,
): Gtk.Widget =>
  (
    <button class="cmd-row" onClicked={onSelect}>
      <box spacing={10}>
        <label label={p.title || p.subtitle} halign={START} />
        {p.title ? (
          <label class="cmd-email" label={p.subtitle} halign={START} hexpand />
        ) : (
          <box hexpand />
        )}
      </box>
    </button>
  ) as Gtk.Widget;

const groupLabel = (t: string): Gtk.Widget =>
  (<label class="palette-group" label={t} halign={START} />) as Gtk.Widget;

// Centered modal command palette with a "Meet with…" people sub-mode. Filtering
// is live; commands are otherwise static.
export default function CommandPalette() {
  let panel: Gtk.Box;
  let root: Gtk.Box;
  let entry: Gtk.Entry;
  let list: Gtk.Box;
  let dispose: (() => void) | null = null;
  let mode: "root" | "meet" | "date" = "root";
  // Meet-mode contact search: real Google contacts when signed in (async,
  // debounced), else the dummy PEOPLE list.
  let meetResults: Suggestion[] = [];
  let meetDebounce: number | null = null;

  const fetchMeet = (q: string) => {
    if (meetDebounce !== null) {
      GLib.source_remove(meetDebounce);
      meetDebounce = null;
    }
    if (!q) {
      meetResults = [];
      render();
      return;
    }
    meetDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
      meetDebounce = null;
      fetchContacts(q)
        .then((r) => {
          meetResults = r;
          render();
        })
        .catch(() => {
          meetResults = [];
          render();
        });
      return GLib.SOURCE_REMOVE;
    });
  };

  // Live people list for the current query (real contacts vs dummy fallback).
  const meetPeople = (q: string): Suggestion[] =>
    googleConfigured()
      ? meetResults
      : PEOPLE.filter(
          (p) =>
            p.title.toLowerCase().includes(q) ||
            p.subtitle.toLowerCase().includes(q),
        );

  const enterMeet = () => {
    mode = "meet";
    meetResults = [];
    entry.set_text("");
    entry.set_placeholder_text("Meet with…");
    entry.grab_focus();
    render();
  };

  const enterDate = () => {
    mode = "date";
    entry.set_text("");
    entry.set_placeholder_text("Jump to date — e.g. 2026-06-15 or Jun 15");
    entry.grab_focus();
    render();
  };

  const today = () => {
    goToday();
    setPaletteOpen(false);
  };

  const step = (dir: number) => {
    stepAnchor(dir);
    setPaletteOpen(false);
  };

  // Start at the current time (snapped to 15 min), one hour long.
  const newEvent = (title: string) => {
    const d = anchor.get();
    const start = Math.round(NOW_HOUR * 4) / 4;
    const ev = createEvent({
      title,
      start,
      end: Math.min(start + 1, 24),
      date: d,
      calendar: defaultCal.get(),
    });
    setSelected({ ev, date: d, isNew: true });
    setPaletteOpen(false);
    return ev;
  };

  const createNew = () => newEvent("New event");

  // Create an event with the chosen person as a *draft* invite (pending) — the
  // user still confirms via "Send invite". Seed the draft after the editor
  // builds (which resets it).
  const meetWith = (p: { title: string; subtitle: string }) => {
    const ev = newEvent(`Meeting with ${p.title || p.subtitle}`);
    draftHolder.event = ev;
    setDraftInvites([p.subtitle]);
  };

  const CALENDAR: Cmd[] = [
    { name: "Create event…", keys: ["C"], action: createNew },
    { name: "Meet with…", keys: ["P"], action: enterMeet },
  ];
  const NAV: Cmd[] = [
    { name: "Go to date…", keys: ["."], action: enterDate },
    { name: "Go to today", keys: ["T"], action: today },
    { name: "Next period", keys: ["→"], action: () => step(1) },
    { name: "Previous period", keys: ["←"], action: () => step(-1) },
  ];

  // Activate the first visible result (Enter): jump to a date, invite the top
  // person, or run the first matching command.
  const activate = () => {
    const raw = entry.get_text().trim();
    if (mode === "date") {
      const d = parseDate(raw);
      if (d) {
        setAnchor(d);
        setPaletteOpen(false);
      }
      return;
    }
    const q = raw.toLowerCase();
    if (mode === "meet") {
      const p = meetPeople(q)[0];
      if (p) meetWith(p);
      return;
    }
    const cmd = [...CALENDAR, ...NAV].find((c) =>
      c.name.toLowerCase().includes(q),
    );
    (cmd?.action ?? (() => setPaletteOpen(false)))();
  };

  function render() {
    clearChildren(list);
    if (dispose) dispose();
    createRoot((d) => {
      dispose = d;
      const q = entry.get_text().toLowerCase().trim();
      if (mode === "date") {
        const d = parseDate(entry.get_text().trim());
        list.append(
          groupLabel(d ? `↵ Jump to ${d.toDateString()}` : "Type a date…"),
        );
        return;
      }
      if (mode === "meet") {
        for (const p of meetPeople(q))
          list.append(PersonRow(p, () => meetWith(p)));
        return;
      }
      const cal = CALENDAR.filter((c) => c.name.toLowerCase().includes(q));
      const nav = NAV.filter((c) => c.name.toLowerCase().includes(q));
      if (cal.length) {
        list.append(groupLabel("Calendar"));
        for (const c of cal) list.append(CmdRow(c));
      }
      if (nav.length) {
        list.append(groupLabel("Navigation"));
        for (const c of nav) list.append(CmdRow(c));
      }
    });
  }

  // On each keystroke: in signed-in meet mode, (debounced) fetch real contacts;
  // otherwise just re-render the static/filtered list.
  const onText = () => {
    if (mode === "meet" && googleConfigured())
      fetchMeet(entry.get_text().trim());
    else render();
  };

  // Reset to command mode and focus the search each time the palette opens.
  paletteOpen.subscribe(() => {
    if (!paletteOpen.get()) return;
    const intent = paletteIntent.get();
    setPaletteIntent("command"); // reset for the next opener
    mode = "root";
    entry.set_text("");
    entry.set_placeholder_text("Type a command…");
    render();
    if (intent === "date") enterDate();
    else if (intent === "meet") enterMeet();
    // (focus is moved onto the entry by modalFocusTrap when the palette opens)
  });

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      setPaletteOpen(false);
      return true;
    }
  }

  return (
    <box
      class="palette-backdrop"
      $={(ref: Gtk.Box) => {
        root = ref;
        // Trap focus on the search entry so Tab can't reach the grid behind the
        // palette; the entry owns Enter (activate), so no onActivate here.
        modalFocusTrap(ref, paletteOpen, {
          panel: () => panel,
          initial: () => entry,
        });
      }}
      visible={paletteOpen((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="palette"
        $={(ref: Gtk.Box) => (panel = ref)}
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.START}
        orientation={Gtk.Orientation.VERTICAL}
      >
        <box class="palette-search" spacing={10}>
          <image iconName="system-search-symbolic" pixelSize={iconPx(16)} />
          <entry
            $={(e: Gtk.Entry) => (entry = e)}
            placeholderText="Type a command…"
            hexpand
            onNotifyText={onText}
            onActivate={activate}
          />
        </box>
        <box
          class="palette-list"
          orientation={Gtk.Orientation.VERTICAL}
          $={(b: Gtk.Box) => {
            list = b;
            render();
          }}
        />
        <box class="palette-foot" spacing={14}>
          <label class="muted" label="↕ Navigate" />
          <label class="muted" label="↵ Select" />
          <label class="muted" label="Esc Close" />
        </box>
      </box>
    </box>
  );
}
