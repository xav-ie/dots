import { createRoot } from "ags";
import { Gdk, Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import GLib from "gi://GLib";
import type { Suggestion } from "./data";

const START = Gtk.Align.START;
const ROW_H = 46; // fixed per-row height (see .suggest-row in style.scss)
const MAX_VISIBLE = 8; // rows shown before the list scrolls

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Bold the matched substring so the query stands out.
function highlight(text: string, q: string): string {
  if (!q) return esc(text);
  const i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return esc(text);
  return (
    esc(text.slice(0, i)) +
    `<span weight="bold" foreground="#ffffff">${esc(text.slice(i, i + q.length))}</span>` +
    esc(text.slice(i + q.length))
  );
}

export function Row(s: Suggestion, q: string, active: boolean): Gtk.Widget {
  const primary = s.title || s.subtitle;
  const secondary = s.title ? s.subtitle : "";
  return (
    <box class={`suggest-row${active ? " sel" : ""}`} spacing={10}>
      <box orientation={Gtk.Orientation.VERTICAL} hexpand>
        <label
          class="sg-primary"
          useMarkup
          label={highlight(primary, q)}
          xalign={0}
        />
        {secondary ? (
          <label
            class="sg-secondary"
            useMarkup
            label={highlight(secondary, q)}
            xalign={0}
          />
        ) : (
          <box />
        )}
      </box>
      {s.dotColor ? (
        <box
          class={`sg-account-dot ev-${s.dotColor}`}
          tooltipText={s.source}
          valign={Gtk.Align.CENTER}
        />
      ) : (
        <box />
      )}
      {s.recent ? (
        <image
          class="sg-recent"
          iconName="document-open-recent-symbolic"
          pixelSize={iconPx(14)}
          valign={Gtk.Align.CENTER}
        />
      ) : (
        <box />
      )}
    </box>
  ) as Gtk.Widget;
}

export interface SuggestFieldProps {
  placeholder: string;
  icon?: string; // primary icon (optional)
  position: Gtk.PositionType; // RIGHT (sidebar) or LEFT (right pane)
  items: Suggestion[];
  // When provided, called on each keystroke (debounced) instead of filtering
  // `items` statically. `items` is used as the initial/empty-query fallback.
  fetchItems?: (q: string) => Promise<Suggestion[]>;
  // Optional fallback when nothing matches (e.g. a typed email becomes a row).
  freeform?: (q: string) => Suggestion | null;
  initial?: string; // prefill the field
  onCommit?: (value: string) => void; // persist on blur
  onSelect?: (value: string) => void; // fires when a row is chosen (Enter/click)
  clearOnSelect?: boolean; // clear the field after selecting (for adding to a list)
  fillTitle?: boolean; // fill with the row's title instead of subtitle
  required?: boolean; // restore the previous value if left empty
  // Show the selection as the placeholder/hint and keep the text empty (the
  // field always reads as a prompt; used for the timezone picker).
  asHint?: boolean;
}

// A text field that filters `items` live and pops a suggestion list. ↑/↓ move,
// Enter selects. The popover's pointing-to rect is sized to the list height
// (deterministically, from row count) so it stays top-aligned with the field.
export default function SuggestField(props: SuggestFieldProps) {
  let listBox: Gtk.Box;
  let pop: Gtk.Popover;
  let entryRef: Gtk.Entry;
  let matches: Suggestion[] = [];
  let active = 0;
  let lastValue = props.initial ?? "";
  let debounce: number | null = null;
  // Disposes the previous batch of rows' reactive bindings (the iconPx zoom
  // binding registers an onCleanup); rebuilt rows need their own tracking root.
  let disposeRows: (() => void) | null = null;

  function rebuild(q: string) {
    clearChildren(listBox);
    if (disposeRows) disposeRows();
    createRoot((dispose) => {
      disposeRows = dispose;
      matches.forEach((s, i) => {
        const row = Row(s, q, i === active);
        // Click a row to select it (Enter still works via the key controller).
        const click = new Gtk.GestureClick();
        click.connect("released", () => {
          active = i;
          choose();
        });
        row.add_controller(click);
        listBox.append(row);
      });
    });
  }

  function applyMatches(q: string, results: Suggestion[]) {
    matches = results;
    if (matches.length === 0 && props.freeform) {
      const f = props.freeform(q);
      if (f) matches = [f];
    }
    active = 0;
    rebuild(q);
    if (!matches.length) {
      pop.popdown();
      return;
    }
    // Size the anchor rect to the (capped) list height so RIGHT/LEFT centering
    // puts the list's top at the field. Deterministic → no drift on type.
    const ew = entryRef.get_width() || 220;
    const ph = Math.min(matches.length, MAX_VISIBLE) * ROW_H + 14;
    pop.set_pointing_to(
      new Gdk.Rectangle({ x: 0, y: 0, width: ew, height: ph }),
    );
    pop.popup();
  }

  function refresh() {
    const q = entryRef.get_text().trim();
    if (debounce !== null) {
      GLib.source_remove(debounce);
      debounce = null;
    }
    if (props.fetchItems) {
      // Empty query: show nothing until the user starts typing.
      if (!q) {
        applyMatches(q, []);
        return;
      }
      debounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
        debounce = null;
        props.fetchItems!(q)
          .then((r) => applyMatches(q, r))
          .catch(() => {
            const f = props.freeform?.(q);
            applyMatches(q, f ? [f] : []);
          });
        return GLib.SOURCE_REMOVE;
      });
    } else {
      const ql = q.toLowerCase();
      const results = q
        ? props.items.filter(
            (s) =>
              s.title.toLowerCase().includes(ql) ||
              s.subtitle.toLowerCase().includes(ql),
          )
        : props.items;
      applyMatches(q, results);
    }
  }

  function move(d: number) {
    if (!matches.length) return;
    active = (active + d + matches.length) % matches.length;
    rebuild(entryRef.get_text().trim());
  }

  function choose() {
    const s = matches[active];
    if (!s) return;
    const value = props.fillTitle ? s.title : s.subtitle || s.title;
    lastValue = value;
    props.onSelect?.(value);
    if (props.asHint) {
      // Show the choice as the prompt; keep the text empty.
      entryRef.set_placeholder_text(value);
      entryRef.set_text("");
      props.onCommit?.(value);
      pop.popdown();
    } else if (props.clearOnSelect) {
      // Adding to a list: clear and keep the suggestion list open for the next
      // entry. Don't popdown — closing this nested popover cascades up and
      // dismisses the floating event-editor popover.
      entryRef.set_text("");
      refresh();
    } else {
      entryRef.set_text(value);
      entryRef.set_position(-1);
      props.onCommit?.(value);
      pop.popdown();
    }
  }

  function onKey(_e: Gtk.EventControllerKey, keyval: number) {
    switch (keyval) {
      case Gdk.KEY_Down:
        move(1);
        return true;
      case Gdk.KEY_Up:
        move(-1);
        return true;
      case Gdk.KEY_Return:
      case Gdk.KEY_KP_Enter:
        choose();
        return true;
      case Gdk.KEY_Escape:
        pop.popdown();
        return true;
    }
    return false;
  }

  return (
    <entry
      class="suggest-field"
      hexpand
      primaryIconName={props.icon ?? ""}
      placeholderText={props.placeholder}
      onNotifyText={refresh}
      $={(entry: Gtk.Entry) => {
        entryRef = entry;
        pop = new Gtk.Popover();
        pop.set_parent(entry);
        pop.set_autohide(false);
        pop.set_has_arrow(false);
        // Keep the popover (and its scroll view) out of the Tab focus chain, so
        // each field is a single tab stop, not two.
        pop.set_can_focus(false);
        pop.set_focusable(false);
        pop.set_position(props.position);
        // The pointing-to rect already top-aligns the list; just a small upward
        // nudge for the chrome, plus a horizontal gap from the field.
        pop.set_offset(props.position === Gtk.PositionType.LEFT ? -14 : 14, -8);
        pop.add_css_class("people-pop");
        listBox = (
          <box class="people-list" orientation={Gtk.Orientation.VERTICAL} />
        ) as Gtk.Box;
        // Cap the height and scroll past MAX_VISIBLE rows (long lists glitch out).
        const scroll = (
          <scrolledwindow
            class="suggest-scroll"
            canFocus={false}
            maxContentHeight={MAX_VISIBLE * ROW_H}
            propagateNaturalHeight
            hscrollbarPolicy={Gtk.PolicyType.NEVER}
          >
            {listBox}
          </scrolledwindow>
        ) as Gtk.Widget;
        pop.set_child(scroll);

        const key = new Gtk.EventControllerKey();
        // Capture phase: intercept Enter/Escape/arrows before GtkText handles
        // them, so Enter selects a suggestion without also firing the entry's
        // default action (which would close the floating event editor).
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key.connect("key-pressed", onKey);
        entry.add_controller(key);

        const focus = new Gtk.EventControllerFocus();
        focus.connect("enter", refresh);
        focus.connect("leave", () => {
          // Required fields restore their prior value when left empty (hint
          // fields are always "empty" by design, so skip them).
          if (!props.asHint && props.required && !entry.get_text().trim()) {
            entry.set_text(lastValue);
          }
          // Only persist a real change — a blur with the value untouched would
          // otherwise count as an edit, popping the recurring edit-scope dialog
          // (and PATCHing a synced event) for nothing.
          if (!props.asHint && entry.get_text() !== lastValue) {
            lastValue = entry.get_text();
            props.onCommit?.(lastValue);
          }
          pop.popdown();
        });
        entry.add_controller(focus);

        // Prefill last, once listBox/pop exist — set_text fires onNotifyText
        // (refresh → rebuild), which would deref listBox before it was created.
        if (props.initial) {
          // asHint shows the value as a prompt; otherwise prefill the text.
          if (props.asHint) entry.set_placeholder_text(props.initial);
          else entry.set_text(props.initial);
        }
      }}
    />
  );
}

export const emailFreeform = (q: string): Suggestion | null =>
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(q.trim())
    ? { title: "", subtitle: q.trim() }
    : null;

// A typed value becomes an "add" option only once it looks like a URL.
export const linkFreeform = (q: string): Suggestion | null => {
  const v = q.trim();
  return /^(https?:\/\/)?([\w-]+\.)+[\w-]{2,}(\/\S*)?$/i.test(v)
    ? { title: "", subtitle: v }
    : null;
};
