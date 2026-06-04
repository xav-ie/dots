import { For, createRoot, createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import {
  ACCOUNTS,
  LOCATIONS,
  TIMEZONES,
  calColor,
  eventColor,
  eventReminders,
  type CalEvent,
} from "./data";
import { EVENT_COLOR_ROWS } from "./palette";
import {
  MINI_DOW,
  TODAY,
  addDays,
  addMonths,
  fmtFullDate,
  fmtMonthYear,
  fmtTime,
  sameDay,
  startOfWeek,
  systemIANA,
} from "./datetime";
import { closeSelected, setSelected, type Selection } from "./state";
import {
  addMeet,
  deleteEvent,
  rev,
  setAllDay,
  setEndDate,
  setEventDate,
  setEventTime,
  setReminders,
  updateEvent,
} from "./store";
import SuggestField, { linkFreeform } from "./SuggestField";
import { Participants } from "./Participants";
import Recurrence from "./Recurrence";
import Select from "./Select";
import { a11y } from "./a11y";

const START = Gtk.Align.START;

// The timezone picker stores the IANA id (ev.timezone) but shows the pretty
// "GMT±N City" label; TIMEZONES carries both (title = label, subtitle = IANA).
const tzLabel = (iana?: string): string | undefined =>
  TIMEZONES.find((t) => t.subtitle === iana)?.title ?? iana;
const tzIana = (label: string): string =>
  TIMEZONES.find((t) => t.title === label)?.subtitle ?? label;

// Calendar the event belongs to, as a dropdown to transfer it between calendars
// (static for the mockup) plus an event-color picker, like Notion.
function CalendarPicker(ev: CalEvent) {
  const current = ev.calendar || "Calendar";
  let pop: Gtk.Popover;
  // Calendars you can write to (computed once) — an event can't live on a
  // read-only calendar, so only these are move targets.
  const writableAccounts = ACCOUNTS.map((a) => ({
    account: a.account,
    calendars: a.calendars.filter((c) => c.writable),
  })).filter((a) => a.calendars.length > 0);
  // Color swatches: repaint the selected ring from the event's EFFECTIVE color
  // (its override, or the calendar color mapped down to an event color) on click
  // and each time the popover opens, so one swatch is always selected.
  const dots: Record<string, Gtk.Button> = {};
  const paintDots = () => {
    const sel = eventColor(ev);
    for (const col in dots)
      if (col === sel) dots[col].add_css_class("sel");
      else dots[col].remove_css_class("sel");
  };
  // The collapsed picker's swatch + name (updated imperatively on a pick, since
  // the event object isn't reactive).
  let headSwatch: Gtk.Box;
  let headLabel: Gtk.Label;
  return (
    <menubutton class="cal-picker info-row">
      <box spacing={10}>
        <box
          class={`swatch ev-${calColor(ev.calendar)}`}
          valign={Gtk.Align.CENTER}
          $={(b: Gtk.Box) => (headSwatch = b)}
        />
        <label
          label={current}
          halign={START}
          hexpand
          ellipsize={3}
          $={(l: Gtk.Label) => (headLabel = l)}
        />
        <image iconName="pan-down-symbolic" pixelSize={iconPx(12)} />
      </box>
      <popover
        class="cal-pop"
        $={(p: Gtk.Popover) => {
          pop = p;
          p.connect("map", paintDots);
        }}
      >
        <box class="cal-menu" orientation={Gtk.Orientation.VERTICAL}>
          {writableAccounts.map((acct) => (
            <box orientation={Gtk.Orientation.VERTICAL}>
              <label
                class="cal-menu-acct"
                label={acct.account}
                halign={START}
              />
              {acct.calendars.map((c) => (
                <button
                  class="cal-menu-item"
                  onClicked={() => {
                    if (c.name !== ev.calendar) {
                      updateEvent(ev.id, "calendar", c.name, true);
                      // ev.calendar/color are updated by the move; reflect them.
                      headSwatch.set_css_classes([
                        "swatch",
                        `ev-${calColor(ev.calendar)}`,
                      ]);
                      headLabel.set_label(c.name);
                      paintDots();
                    }
                    pop.popdown();
                  }}
                >
                  <box spacing={8}>
                    <box class="cal-check">
                      {c.name === current ? (
                        <image
                          iconName="object-select-symbolic"
                          pixelSize={iconPx(12)}
                        />
                      ) : (
                        <box />
                      )}
                    </box>
                    <box
                      class={`swatch ev-${c.color}`}
                      valign={Gtk.Align.CENTER}
                    />
                    <label
                      label={c.name}
                      halign={START}
                      hexpand
                      ellipsize={3}
                    />
                  </box>
                </button>
              ))}
            </box>
          ))}
          <label class="cal-menu-acct" label="Event color" halign={START} />
          <box
            class="color-grid"
            orientation={Gtk.Orientation.VERTICAL}
            spacing={6}
          >
            {EVENT_COLOR_ROWS.map((row) => (
              <box class="color-row" spacing={6}>
                {row.map((col) => (
                  <button
                    class={`color-dot${col === eventColor(ev) ? " sel" : ""}`}
                    $={(b: Gtk.Button) => (dots[col] = b)}
                    onClicked={() => {
                      if (col !== eventColor(ev)) {
                        updateEvent(ev.id, "color", col, true);
                        paintDots();
                      }
                      pop.popdown();
                    }}
                  >
                    <box class={`swatch ev-${col}`} />
                  </button>
                ))}
              </box>
            ))}
          </box>
        </box>
      </popover>
    </menubutton>
  );
}

// Date field: shows a date, opens a mini-calendar to change it. With `onPick` it
// drives a custom setter (the end date); otherwise it moves the event's start day.
function DatePicker(ev: CalEvent, date: Date, onPick?: (d: Date) => void) {
  let pop: Gtk.Popover;
  let gridBox: Gtk.Box;
  let titleLabel: Gtk.Label;
  let valueLabel: Gtk.Label;
  let dispose: (() => void) | null = null;
  let cur = date; // the currently-shown value (updates on pick, no full rebuild)
  let shown = new Date(date.getFullYear(), date.getMonth(), 1);

  const pick = (d: Date) => {
    pop.popdown();
    // Re-picking the day already shown is a no-op — skip it so a recurring event
    // doesn't raise the edit-scope dialog for an unchanged date.
    if (sameDay(d, cur)) return;
    cur = d;
    valueLabel.set_label(fmtFullDate(d));
    if (onPick) onPick(d);
    else {
      setEventDate(ev.id, d);
      setSelected({ ev, date: d });
    }
  };

  const render = () => {
    clearChildren(gridBox);
    titleLabel.set_label(fmtMonthYear(shown));
    if (dispose) dispose();
    createRoot((d) => {
      dispose = d;
      const dowRow = (<box class="mini-row" homogeneous />) as Gtk.Box;
      MINI_DOW.forEach((w) =>
        dowRow.append((<label class="mini-dow" label={w} />) as Gtk.Widget),
      );
      gridBox.append(dowRow);
      const start = startOfWeek(
        new Date(shown.getFullYear(), shown.getMonth(), 1),
      );
      for (let wk = 0; wk < 6; wk++) {
        const row = (<box class="mini-row" homogeneous />) as Gtk.Box;
        for (let i = 0; i < 7; i++) {
          const cell = addDays(start, wk * 7 + i);
          const cls = ["mini-day"];
          if (cell.getMonth() !== shown.getMonth()) cls.push("dim");
          const today = sameDay(cell, TODAY);
          if (today) cls.push("today");
          if (sameDay(cell, cur)) cls.push("sel"); // selected wins over today
          row.append(
            (
              <button class={cls.join(" ")} onClicked={() => pick(cell)}>
                <label label={`${cell.getDate()}`} />
              </button>
            ) as Gtk.Widget,
          );
        }
        gridBox.append(row);
      }
    });
  };

  return (
    <menubutton class="date-field" halign={START}>
      <label
        label={fmtFullDate(date)}
        halign={START}
        $={(l: Gtk.Label) => (valueLabel = l)}
      />
      <popover class="date-pop" $={(p: Gtk.Popover) => (pop = p)}>
        <box
          class="date-cal"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={2}
        >
          <box class="mini-head">
            <label
              class="mini-title"
              $={(l: Gtk.Label) => (titleLabel = l)}
              label={fmtMonthYear(shown)}
              hexpand
              halign={START}
            />
            <button
              class="icon-btn"
              tooltipText="Previous month"
              onClicked={() => {
                shown = addMonths(shown, -1);
                render();
              }}
              $={(b: Gtk.Button) => a11y(b, "Previous month")}
            >
              <image iconName="pan-start-symbolic" pixelSize={iconPx(12)} />
            </button>
            <button
              class="icon-btn"
              tooltipText="Next month"
              onClicked={() => {
                shown = addMonths(shown, 1);
                render();
              }}
              $={(b: Gtk.Button) => a11y(b, "Next month")}
            >
              <image iconName="pan-end-symbolic" pixelSize={iconPx(12)} />
            </button>
          </box>
          <box
            orientation={Gtk.Orientation.VERTICAL}
            spacing={2}
            $={(b: Gtk.Box) => {
              gridBox = b;
              render();
            }}
          />
        </box>
      </popover>
    </menubutton>
  );
}

// Editable title: a wrapping label that swaps to an entry on click (a TextView
// proved crashy). Persists on Enter / blur.
function TitleField(ev: CalEvent, isNew = false) {
  let stack: Gtk.Stack;
  let entry: Gtk.Entry;
  let label: Gtk.Label;
  let viewBtn: Gtk.Button;
  const commit = () => {
    const t = entry.get_text().trim();
    if (t) {
      label.set_label(t);
      // Only persist a real change — a blur/teardown commit of the unchanged
      // title would otherwise count as an edit (and PATCH a synced event).
      if (t !== ev.title) updateEvent(ev.id, "title", t, true);
    }
    stack.set_visible_child_name("view");
  };
  // New events open straight into the title entry, selected for quick rename.
  const startEditing = (selectAll = true) => {
    entry.set_text(label.get_label());
    stack.set_visible_child_name("edit");
    entry.grab_focus();
    if (selectAll) entry.select_region(0, -1);
    else entry.set_position(-1);
  };
  return (
    <stack
      class="info-title-stack"
      $={(s: Gtk.Stack) => {
        stack = s;
        // On selection move keyboard focus to the title (but stay in view mode);
        // new events open straight into edit so you can type the name.
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
          if (isNew) startEditing(true);
          else viewBtn.grab_focus();
          return GLib.SOURCE_REMOVE;
        });
      }}
    >
      <button
        name="view"
        $type="named"
        class="info-title-btn"
        $={(b: Gtk.Button) => (viewBtn = b)}
        onClicked={() => startEditing()}
      >
        <label
          class="info-title"
          $={(l: Gtk.Label) => (label = l)}
          label={ev.title}
          wrap
          halign={START}
          xalign={0}
        />
      </button>
      <entry
        name="edit"
        $type="named"
        class="info-title-edit"
        onActivate={commit}
        $={(e: Gtk.Entry) => {
          entry = e;
          const f = new Gtk.EventControllerFocus();
          f.connect("leave", commit);
          e.add_controller(f);
        }}
      />
    </stack>
  );
}

// Conferencing row: when the event has a Google Meet link, show a row that opens
// it; otherwise an "Add Google Meet" button that provisions one on Google.
function Conferencing(ev: CalEvent) {
  const [link, setLink] = createState(ev.meetLink ?? "");
  // Locks the add button between click and provisioning — a second create while
  // the first is in flight hits Google's rate limit (403).
  const [busy, setBusy] = createState(false);
  const open = (url: string) => Gio.AppInfo.launch_default_for_uri(url, null);
  const add = () => {
    if (busy.get()) return;
    setBusy(true);
    void addMeet(ev).finally(() => {
      setBusy(false);
      setLink(ev.meetLink ?? "");
    });
  };
  return (
    <box>
      {/* Has a Meet link → click to join. */}
      <button
        class="info-row conf join"
        visible={link((l) => !!l)}
        onClicked={() => open(link.get())}
      >
        <box spacing={10}>
          <image iconName="camera-web-symbolic" pixelSize={iconPx(15)} />
          <box orientation={Gtk.Orientation.VERTICAL} hexpand halign={START}>
            <label label="Google Meet" halign={START} />
            <label
              class="conf-link muted"
              label={link((l) => l.replace(/^https?:\/\//, ""))}
              halign={START}
              ellipsize={3}
            />
          </box>
          <image iconName="go-next-symbolic" pixelSize={iconPx(13)} />
        </box>
      </button>
      {/* No link yet → add one. Disabled + spinning while provisioning so a
          double-click can't fire a second (rate-limited) create. */}
      <button
        class="info-row conf add"
        visible={link((l) => !l)}
        sensitive={busy((b) => !b)}
        onClicked={add}
      >
        <box spacing={10}>
          <image iconName="camera-web-symbolic" pixelSize={iconPx(15)} />
          <label
            label={busy((b) => (b ? "Adding Google Meet…" : "Add Google Meet"))}
            halign={START}
            hexpand
          />
          <Gtk.Spinner
            spinning={busy((b) => b)}
            visible={busy((b) => b)}
            valign={Gtk.Align.CENTER}
          />
          <image
            iconName="list-add-symbolic"
            pixelSize={iconPx(13)}
            visible={busy((b) => !b)}
          />
        </box>
      </button>
    </box>
  );
}

// Parse a typed time: "13:30", "1:30 PM", "1pm", "9". Returns hour-of-day float
// (0–24) or null. A bare 1–12 with no meridiem is taken literally (24h).
function parseTime(s: string): number | null {
  const m = s
    .trim()
    .toLowerCase()
    .match(/^(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?$/);
  if (!m) return null;
  let h = +m[1];
  const min = m[2] ? +m[2] : 0;
  const ap = m[3]?.replace(/\./g, "");
  if (min > 59) return null;
  if (ap) {
    if (h < 1 || h > 12) return null;
    if (ap === "pm" && h < 12) h += 12;
    if (ap === "am" && h === 12) h = 0;
  } else if (h > 23) return null;
  return h + min / 60;
}

// Editable start/end times: click a time to type a new one. Editing the start
// keeps the duration if it would otherwise invert; the end must stay after it.
// A single editable time (start or end): click to type a new time. Editing the
// start keeps the duration if it would otherwise invert; the end must stay after
// the start. Repaints on `rev` so a grid drag/resize is reflected here too.
function TimeField(ev: CalEvent, which: "start" | "end"): Gtk.Widget {
  let stack: Gtk.Stack;
  let entry: Gtk.Entry;
  let lbl: Gtk.Label;
  const cur = () => (which === "start" ? ev.start : ev.end);
  onCleanup(rev.subscribe(() => lbl.set_label(fmtTime(cur()))));
  const commit = () => {
    const t = parseTime(entry.get_text());
    if (t != null) {
      if (which === "start") {
        // Multi-day: the end is on a later day (its hour may be ≤ start), so keep
        // it; the same-day duration-preservation heuristic would corrupt it.
        const end = ev.endDate
          ? ev.end
          : t >= ev.end
            ? t + (ev.end - ev.start)
            : ev.end;
        // Skip a no-op (opened the field then tabbed away unchanged) — it would
        // otherwise pop the recurring edit-scope dialog for nothing.
        if (t !== ev.start || end !== ev.end) setEventTime(ev.id, t, end);
      } else if (ev.endDate || t > ev.start) {
        // A multi-day event's end is on a later day, so its hour can be ≤ start.
        if (t !== ev.end) setEventTime(ev.id, ev.start, t);
      }
      lbl.set_label(fmtTime(cur()));
    }
    stack.set_visible_child_name("view");
  };
  return (
    <stack class="time-stack" $={(s: Gtk.Stack) => (stack = s)}>
      <button
        name="view"
        $type="named"
        class="time-btn"
        onClicked={() => {
          entry.set_text(fmtTime(cur()));
          stack.set_visible_child_name("edit");
          entry.grab_focus();
          entry.select_region(0, -1);
        }}
      >
        <label
          class="time-val"
          $={(l: Gtk.Label) => (lbl = l)}
          label={fmtTime(cur())}
          halign={START}
          xalign={0}
        />
      </button>
      <entry
        name="edit"
        $type="named"
        class="time-edit"
        widthChars={7}
        maxWidthChars={7}
        onActivate={commit}
        $={(e: Gtk.Entry) => {
          entry = e;
          const f = new Gtk.EventControllerFocus();
          f.connect("leave", commit);
          e.add_controller(f);
        }}
      />
    </stack>
  ) as Gtk.Widget;
}

// Attachment links: a field that only offers to add a value once it looks like
// a URL (mirroring the email participant field), plus the saved-link list.
function Attachments(ev: CalEvent) {
  // Links are newline-separated (URLs can contain commas — see gwrite.ts).
  const initial = ev.links ? ev.links.split("\n").filter(Boolean) : [];
  const [saved, setSaved] = createState(initial);
  const add = (url: string) => {
    if (!url || saved.get().includes(url)) return;
    const next = [...saved.get(), url];
    setSaved(next);
    ev.links = next.join("\n");
    updateEvent(ev.id, "links", ev.links);
  };
  const remove = (url: string) => {
    const next = saved.get().filter((x) => x !== url);
    setSaved(next);
    ev.links = next.join("\n");
    updateEvent(ev.id, "links", ev.links);
  };
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <SuggestField
        placeholder="Add links and attachments"
        icon="mail-attachment-symbolic"
        position={Gtk.PositionType.LEFT}
        items={[]}
        freeform={linkFreeform}
        onSelect={add}
        clearOnSelect
      />
      <box
        class="attachments"
        orientation={Gtk.Orientation.VERTICAL}
        spacing={1}
      >
        <For each={saved}>
          {(url: string) => (
            <box class="attachment" spacing={8}>
              <image
                iconName="mail-attachment-symbolic"
                pixelSize={iconPx(13)}
                valign={Gtk.Align.CENTER}
              />
              <label label={url} halign={START} hexpand ellipsize={3} />
              <button
                class="attach-x"
                onClicked={() => remove(url)}
                $={(b: Gtk.Button) => a11y(b, `Remove attachment ${url}`)}
              >
                <image
                  iconName="window-close-symbolic"
                  pixelSize={iconPx(12)}
                />
              </button>
            </box>
          )}
        </For>
      </box>
    </box>
  ) as Gtk.Widget;
}

const REMINDER_PRESETS = [0, 5, 10, 15, 30, 60, 120, 1440];

function reminderLabel(m: number): string {
  if (m === 0) return "At time of event";
  if (m < 60) return `${m} minutes before`;
  if (m < 1440) {
    const h = m / 60;
    return `${h} hour${h === 1 ? "" : "s"} before`;
  }
  const d = m / 1440;
  return `${d} day${d === 1 ? "" : "s"} before`;
}

function reminderSummary(mins: number[]): string {
  if (!mins.length) return "No notification";
  return [...mins]
    .sort((a, b) => a - b)
    .map(reminderLabel)
    .join(", ");
}

// Notification reminders: a multi-select dropdown of preset offsets with a
// checkmark, mirroring the recurrence picker. Toggling writes the new set to
// Google (popup reminders), which the desktop notifier reads.
function Reminders(ev: CalEvent) {
  const [cur, setCur] = createState(
    [...eventReminders(ev)].sort((a, b) => a - b),
  );
  let listBox: Gtk.Box;
  let disposeList: (() => void) | null = null;

  const toggle = (m: number) => {
    const has = cur.get().includes(m);
    const next = (
      has ? cur.get().filter((x) => x !== m) : [...cur.get(), m]
    ).sort((a, b) => a - b);
    setCur(next);
    setReminders(ev.id, next);
    render();
  };

  const render = () => {
    clearChildren(listBox);
    if (disposeList) disposeList();
    createRoot((dispose) => {
      disposeList = dispose;
      for (const m of REMINDER_PRESETS) {
        const on = cur.get().includes(m);
        listBox.append(
          (
            <button class="recur-item" onClicked={() => toggle(m)}>
              <box spacing={8}>
                <box class="recur-check">
                  {on ? (
                    <image
                      iconName="object-select-symbolic"
                      pixelSize={iconPx(12)}
                    />
                  ) : (
                    <box />
                  )}
                </box>
                <label label={reminderLabel(m)} halign={START} hexpand />
              </box>
            </button>
          ) as Gtk.Widget,
        );
      }
    });
  };

  return (
    <menubutton class="info-row recur-field">
      <box spacing={8}>
        <image iconName="alarm-symbolic" pixelSize={iconPx(15)} />
        <label
          label={cur((c) => reminderSummary(c))}
          halign={START}
          hexpand
          ellipsize={3}
        />
        <image iconName="pan-down-symbolic" pixelSize={iconPx(12)} />
      </box>
      <popover
        class="recur-pop"
        $={(p: Gtk.Popover) => p.connect("map", render)}
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

// Event detail content, shared between the right pane and the click popover.
export default function EventInfo(sel: Selection) {
  const { ev, date } = sel;
  // The Start/End rows come from the event's own date/endDate (not the clicked
  // day) — for a multi-day event you may have clicked a later segment.
  const startDate = ev.date
    ? new Date(ev.date[0], ev.date[1], ev.date[2])
    : date;
  // Drives the time-row visibility so the all-day toggle updates it live.
  const [allDayLocal, setAllDayLocal] = createState(ev.allDay ?? false);
  // Delete needs a confirm step — a misclick destroys a real Google event (and
  // cancels its guests) — so the trash button always arms an inline "Delete?"
  // first. For a recurring event the This/Following/All scope dialog only appears
  // on the second (confirming) click, as part of the actual delete.
  const [confirmDel, setConfirmDel] = createState(false);
  let delBtn: Gtk.Button;
  let closeBtn: Gtk.Button;
  const doDelete = () => {
    // Clear focus before the editor tears down — otherwise GTK restores focus
    // into the week grid, whose scrolledwindow then scrolls to that chip.
    (delBtn?.get_root() as Gtk.Window | null)?.set_focus(null);
    deleteEvent(ev.id);
    setSelected(null);
  };
  // First click arms the confirm (a misclick destroys a real Google event); the
  // second deletes — and only then does a recurring event raise its scope dialog.
  // The button MORPHS rather than swapping with a hidden sibling: hiding the
  // just-clicked button would bounce focus into the grid and scroll it.
  const onDelClick = () => {
    if (confirmDel.get()) doDelete();
    else setConfirmDel(true);
  };
  return (
    <box class="event-info" orientation={Gtk.Orientation.VERTICAL} spacing={9}>
      <box class="info-head" spacing={6}>
        <box hexpand />
        <button
          class={confirmDel((c) => `icon-btn danger${c ? " confirm-del" : ""}`)}
          tooltipText={confirmDel((c) =>
            c ? "Confirm delete" : "Delete event",
          )}
          onClicked={onDelClick}
          $={(b: Gtk.Button) => {
            delBtn = b;
            a11y(
              b,
              confirmDel((c) => (c ? "Confirm delete event" : "Delete event")),
            );
          }}
        >
          <box>
            <image
              iconName="user-trash-symbolic"
              pixelSize={iconPx(14)}
              visible={confirmDel((c) => !c)}
            />
            <label label="Delete?" visible={confirmDel((c) => c)} />
          </box>
        </button>
        <button
          class="icon-btn"
          visible={confirmDel((c) => c)}
          tooltipText="Cancel delete"
          onClicked={() => {
            setConfirmDel(false);
            // This button just hid; keep focus on the (morphed-back) delete
            // button instead of letting it bounce into the grid.
            delBtn?.grab_focus();
          }}
          $={(b: Gtk.Button) => a11y(b, "Cancel delete")}
        >
          <image iconName="edit-undo-symbolic" pixelSize={iconPx(13)} />
        </button>
        <button
          class="icon-btn"
          tooltipText="Close (Esc)"
          onClicked={() => {
            // Clear focus before teardown so GTK doesn't restore it into the week
            // grid (which would scroll to the chip). Mirrors doDelete.
            (closeBtn?.get_root() as Gtk.Window | null)?.set_focus(null);
            closeSelected();
          }}
          $={(b: Gtk.Button) => {
            closeBtn = b;
            a11y(b, "Close event details");
          }}
        >
          <image iconName="window-close-symbolic" pixelSize={iconPx(14)} />
        </button>
      </box>

      {TitleField(ev, sel.isNew)}

      {/* All-day toggle on its own row, first. */}
      <box class="info-row date-row" spacing={8}>
        <label class="muted" label="All-day" valign={Gtk.Align.CENTER} />
        <box hexpand />
        <Gtk.Switch
          active={ev.allDay ?? false}
          valign={Gtk.Align.CENTER}
          $={(sw: Gtk.Switch) =>
            sw.connect("notify::active", () => {
              const on = sw.get_active();
              if (on === !!ev.allDay) return;
              setAllDay(ev.id, on);
              setAllDayLocal(on); // hide/show the time fields live
            })
          }
        />
      </box>

      {/* Start: date then time. */}
      <box class="info-row date-row" spacing={8}>
        <label class="muted date-lbl" label="Start" valign={Gtk.Align.CENTER} />
        {DatePicker(ev, startDate)}
        <box visible={allDayLocal((a) => !a)}>{TimeField(ev, "start")}</box>
      </box>

      {/* End: date then time (a later day makes it a multi-day span). */}
      <box class="info-row date-row" spacing={8}>
        <label class="muted date-lbl" label="End" valign={Gtk.Align.CENTER} />
        {DatePicker(
          ev,
          ev.endDate
            ? new Date(ev.endDate[0], ev.endDate[1], ev.endDate[2])
            : startDate,
          (d) => setEndDate(ev.id, d),
        )}
        <box visible={allDayLocal((a) => !a)}>{TimeField(ev, "end")}</box>
      </box>

      <SuggestField
        placeholder="Time zone"
        icon="preferences-system-time-symbolic"
        position={Gtk.PositionType.LEFT}
        items={TIMEZONES}
        initial={tzLabel(ev.timezone ?? systemIANA()) ?? systemIANA()}
        onSelect={(v) => {
          // Skip re-selecting the zone already in effect — an unchanged pick
          // would still PATCH the recurring series' base.
          if (tzIana(v) !== (ev.timezone ?? systemIANA()))
            updateEvent(ev.id, "timezone", tzIana(v));
        }}
        fillTitle
        asHint
      />

      {Recurrence(ev, date)}

      {Reminders(ev)}

      <Gtk.Separator />

      {Participants(ev)}

      {Conferencing(ev)}
      <SuggestField
        placeholder="Location"
        icon="mark-location-symbolic"
        position={Gtk.PositionType.LEFT}
        items={LOCATIONS}
        initial={ev.address}
        onCommit={(v) => updateEvent(ev.id, "address", v)}
      />

      <Gtk.Separator />

      {Attachments(ev)}

      <label class="info-section" label="Description" halign={START} />
      <scrolledwindow class="desc-scroll">
        <Gtk.TextView
          class="desc-area"
          wrapMode={Gtk.WrapMode.WORD}
          acceptsTab={false}
          $={(tv: Gtk.TextView) => {
            const buf = tv.get_buffer();
            if (ev.description) buf.set_text(ev.description, -1);
            // Persist once on blur rather than per keystroke.
            const focus = new Gtk.EventControllerFocus();
            focus.connect("leave", () => {
              const [s, e] = buf.get_bounds();
              const text = buf.get_text(s, e, false);
              // Only persist a real change — an unchanged blur would needlessly
              // PATCH the (synced) event.
              if (text !== (ev.description ?? ""))
                updateEvent(ev.id, "description", text);
            });
            tv.add_controller(focus);
          }}
        />
      </scrolledwindow>

      {CalendarPicker(ev)}
      <box class="info-row busy" spacing={10}>
        <Select
          class="mini-select"
          value={ev.freeBusy ?? "Busy"}
          options={["Busy", "Free"]}
          onChange={(v) => updateEvent(ev.id, "freeBusy", v)}
        />
        <Select
          class="mini-select"
          value={ev.visibility ?? "Default visibility"}
          options={["Default visibility", "Public", "Private"]}
          onChange={(v) => updateEvent(ev.id, "visibility", v)}
        />
      </box>
    </box>
  );
}
