import { createRoot, createState } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import type { CalEvent } from "./data";
import { updateEvent } from "./store";
import { recurHolder, setRecurDialog } from "./state";
import {
  parseRecur,
  recurKey,
  recurLabel,
  recurPresets,
  type Recur,
} from "./recur";
import { parseRRULE } from "./gwrite";
import { parseEventId } from "./gmap";
import { getEvent } from "./rest";

const START = Gtk.Align.START;

// "Every week on …" recurrence dropdown: presets + a Custom… entry that opens
// the Repeat dialog. The chosen rule shows a checkmark; a non-preset (custom)
// rule is listed explicitly above Custom….
export default function Recurrence(ev: CalEvent, date: Date) {
  const [cur, setCur] = createState(parseRecur(ev.recur));
  let pop: Gtk.Popover;
  let listBox: Gtk.Box;
  // The rows carry reactive iconPx bindings, so each rebuild needs its own root.
  let disposeList: (() => void) | null = null;

  // Synced recurring occurrences arrive without their rule (singleEvents expands
  // them); fetch the series base's RRULE once so the dropdown shows it correctly.
  if (ev.recurringEventId && !ev.recur && ev.id) {
    const t = parseEventId(ev.id);
    if (t)
      void getEvent(t.account, t.calId, ev.recurringEventId)
        .then((g) => parseRRULE(g.recurrence))
        .then((r) => {
          if (r) {
            ev.recur = JSON.stringify(r);
            setCur(r);
          }
        })
        .catch(() => {});
  }

  const choose = (r: Recur | null) => {
    pop.popdown();
    // Re-picking the current rule is a no-op — skip it so a recurring event
    // doesn't raise the edit-scope dialog for an unchanged repeat.
    if (recurKey(r) === recurKey(cur.get())) return;
    setCur(r);
    updateEvent(ev.id, "recur", r ? JSON.stringify(r) : "");
  };

  const openCustom = () => {
    pop.popdown();
    recurHolder.date = date;
    recurHolder.initial = cur.get() ?? {
      freq: "week",
      interval: 1,
      weekdays: [date.getDay()],
      ends: { type: "never" },
    };
    recurHolder.apply = (r) => choose(r);
    setRecurDialog(true);
  };

  const optionRow = (r: Recur | null, onClick: () => void) => {
    const { primary, secondary } = recurLabel(r, date);
    const on = recurKey(cur.get()) === recurKey(r);
    return (
      <button class="recur-item" onClicked={onClick}>
        <box spacing={8}>
          <box class="recur-check">
            {on ? (
              <image iconName="object-select-symbolic" pixelSize={iconPx(12)} />
            ) : (
              <box />
            )}
          </box>
          <label label={primary} halign={START} />
          {secondary ? (
            <label class="recur-sec" label={secondary} halign={START} hexpand />
          ) : (
            <box hexpand />
          )}
        </box>
      </button>
    ) as Gtk.Widget;
  };

  const render = () => {
    clearChildren(listBox);
    if (disposeList) disposeList();
    createRoot((dispose) => {
      disposeList = dispose;
      listBox.append(optionRow(null, () => choose(null)));
      const presets = recurPresets(date);
      for (const p of presets) listBox.append(optionRow(p, () => choose(p)));
      const c0 = cur.get();
      if (c0 && !presets.some((p) => recurKey(p) === recurKey(c0))) {
        listBox.append((<Gtk.Separator />) as Gtk.Widget);
        listBox.append(optionRow(c0, () => choose(c0)));
      }
      listBox.append((<Gtk.Separator />) as Gtk.Widget);
      listBox.append(
        (
          <button class="recur-item" onClicked={openCustom}>
            <box spacing={8}>
              <box class="recur-check" />
              <label label="Custom…" halign={START} hexpand />
            </box>
          </button>
        ) as Gtk.Widget,
      );
    });
  };

  return (
    <menubutton class="info-row recur-field">
      <box spacing={8}>
        <image
          iconName="media-playlist-repeat-symbolic"
          pixelSize={iconPx(15)}
        />
        <label
          label={cur((c) => recurLabel(c, date).primary)}
          halign={START}
          ellipsize={3}
        />
        <label
          class="muted"
          label={cur((c) => recurLabel(c, date).secondary)}
          halign={START}
          hexpand
          ellipsize={3}
        />
        <image iconName="pan-down-symbolic" pixelSize={iconPx(12)} />
      </box>
      <popover
        class="recur-pop"
        $={(p: Gtk.Popover) => {
          pop = p;
          p.connect("map", render);
        }}
      >
        <box
          class="recur-menu"
          orientation={Gtk.Orientation.VERTICAL}
          $={(b: Gtk.Box) => (listBox = b)}
        />
      </popover>
    </menubutton>
  );
}
