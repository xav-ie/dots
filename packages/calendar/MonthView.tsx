import { For, createComputed, createRoot } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import {
  allDayOn,
  eventColor,
  isBirthday,
  isRecurringEvent,
  eventsOn,
  spanPart,
  type CalEvent,
} from "./data";
import { liveEvent, rev } from "./store";
import {
  TODAY,
  fmtHour,
  fmtMonthYear,
  monthGrid,
  sameDay,
  type MiniCell,
} from "./datetime";
import { anchor, hiddenCals, setAnchor, setView } from "./state";
import { pickEvent } from "./eventPopup";
import { a11y } from "./a11y";

const START = Gtk.Align.START;
const MAX_ROWS = 4; // events shown per cell before "N more"
const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Screen-reader name for a month chip: the color dot and time text alone are
// invisible/ambiguous to Orca, so fold day, title, time, calendar and the
// recurring marker into one spoken phrase.
function eventLabel(ev: CalEvent, date: Date): string {
  const when = ev.allDay ? "all day" : fmtHour(ev.start);
  return [
    `${DOW[date.getDay()]} ${date.getDate()}`,
    ev.title,
    when,
    ev.calendar ? `${ev.calendar} calendar` : null,
    isRecurringEvent(ev) ? "recurring" : null,
  ]
    .filter(Boolean)
    .join(", ");
}

// One event line inside a month cell: colored dot + time + title. A multi-day
// all-day event renders as a filled span bar (rounded only on its first/last
// day), with the title shown on the start day and at each week's start.
function MonthEvent(ev: CalEvent, date: Date): Gtk.Widget {
  let btn: Gtk.Button;
  const part = spanPart(ev, date);
  const span = part !== "single";
  const showTitle = !span || part === "start" || date.getDay() === 0;
  const cls = ["m-event"];
  if (span) cls.push("m-span", `ev-${eventColor(ev)}`, `m-span-${part}`);
  return (
    <button
      class={cls.join(" ")}
      $={(b: Gtk.Button) => {
        btn = b;
        a11y(b, eventLabel(ev, date));
      }}
      onClicked={() => {
        // Multi-day chips are per-day copies; open the real event at its start.
        const real = liveEvent(ev.id) ?? ev;
        const d =
          ev.endDate && real.date
            ? new Date(real.date[0], real.date[1], real.date[2])
            : date;
        pickEvent(btn, { ev: real, date: d });
      }}
    >
      <box spacing={5}>
        {span ? (
          <box />
        ) : ev.allDay ? (
          <box class={`m-bar ev-${eventColor(ev)}`} />
        ) : (
          <box class={`m-dot ev-${eventColor(ev)}`} valign={Gtk.Align.CENTER} />
        )}
        {span || ev.allDay ? (
          <box />
        ) : (
          <label class="m-time" label={fmtHour(ev.start)} />
        )}
        {!showTitle ? (
          // Reserve line height so a continuation bar matches a titled line.
          <label class="m-title" label="" hexpand />
        ) : isBirthday(ev.title) ? (
          <box spacing={4} hexpand>
            <image
              iconName="gift-symbolic"
              pixelSize={iconPx(11)}
              valign={Gtk.Align.CENTER}
            />
            <label class="m-title" label={ev.title} ellipsize={3} hexpand />
          </box>
        ) : (
          <label
            class="m-title"
            label={ev.title}
            halign={START}
            ellipsize={3}
            hexpand
          />
        )}
        {isRecurringEvent(ev) && showTitle ? (
          <image
            class="m-recur muted"
            iconName="media-playlist-repeat-symbolic"
            pixelSize={iconPx(10)}
            valign={Gtk.Align.CENTER}
          />
        ) : (
          <box />
        )}
      </box>
    </button>
  ) as Gtk.Widget;
}

function MonthCell(cell: MiniCell) {
  const hidden = hiddenCals.get();
  const allDay: CalEvent[] = allDayOn(cell.date).map((a) => ({
    id: a.id,
    title: a.title,
    color: a.color,
    calendar: a.calendar,
    address: a.address,
    description: a.description,
    recurringEventId: a.recurringEventId,
    start: 0,
    end: 0,
    allDay: true,
    date: a.date,
    endDate: a.endDate,
  }));
  const timed = eventsOn(cell.date);
  const items = [...allDay, ...timed].filter(
    (e) => !hidden.has(e.calendar ?? ""),
  );
  const shown = items.slice(0, MAX_ROWS);
  const extra = items.length - shown.length;
  const firstOfMonth = cell.n === 1;

  return (
    <box
      class={`m-cell${cell.dim ? " dim" : ""}`}
      orientation={Gtk.Orientation.VERTICAL}
      hexpand
      vexpand
    >
      <box class="m-cell-head" spacing={4}>
        <box hexpand />
        {firstOfMonth ? (
          <label
            class="m-month"
            label={fmtMonthYear(cell.date).split(" ")[0]}
          />
        ) : (
          <box />
        )}
        <label
          class={`m-date${cell.today ? " today" : ""}`}
          label={`${cell.n}`}
        />
      </box>
      {shown.map((e) => MonthEvent(e, cell.date))}
      {extra > 0 ? (
        <button
          class="m-more"
          $={(b: Gtk.Button) =>
            a11y(
              b,
              `Show ${extra} more events on ${DOW[cell.date.getDay()]} ${cell.n}`,
            )
          }
          onClicked={() => {
            setAnchor(cell.date);
            setView("day");
          }}
        >
          <label label={`${extra} more`} halign={START} />
        </button>
      ) : (
        <box />
      )}
    </box>
  );
}

export default function MonthView() {
  // Rebuild on anchor/calendar changes; dispose prior interactive widgets.
  const weeks = createComputed(() => {
    hiddenCals();
    rev(); // rebuild when an event's color/calendar changes
    return monthGrid(anchor());
  });

  return (
    <box class="month" orientation={Gtk.Orientation.VERTICAL} vexpand>
      <box class="m-dow-row">
        {DOW.map((d) => (
          <label class="m-dow" label={d} hexpand />
        ))}
      </box>
      <box
        class="m-grid"
        orientation={Gtk.Orientation.VERTICAL}
        vexpand
        $={(self: Gtk.Box) => {
          let dispose: (() => void) | null = null;
          const build = () => {
            clearChildren(self);
            if (dispose) dispose();
            createRoot((d) => {
              dispose = d;
              for (const week of weeks()) {
                const row = (
                  <box class="m-row" homogeneous hexpand vexpand />
                ) as Gtk.Box;
                for (const cell of week)
                  row.append(MonthCell(cell) as Gtk.Widget);
                self.append(row);
              }
            });
          };
          build();
          weeks.subscribe(build);
        }}
      />
    </box>
  );
}
