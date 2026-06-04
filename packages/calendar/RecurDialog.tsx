import { Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import Graphene from "gi://Graphene";
import { recurDialog, recurHolder, setRecurDialog } from "./state";
import { modalFocusTrap } from "./focusTrap";
import type { Recur } from "./recur";

const FREQS: Recur["freq"][] = ["day", "week", "month", "year"];
const DOW2 = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];
const MON = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
const C = Gtk.Align.CENTER;

// Custom "Repeat" dialog: Every N [freq], weekday toggles (week only), and an
// Ends Never / On <date> / After <n> times choice. Built once; seeded from
// recurHolder.initial each time it opens.
export default function RecurDialog() {
  let panel: Gtk.Box;
  let root: Gtk.Box;
  let intervalSpin: Gtk.SpinButton;
  let freqDrop: Gtk.DropDown;
  let weekRow: Gtk.Box;
  const dayBtns: Gtk.ToggleButton[] = [];
  let endNever: Gtk.CheckButton;
  let endOn: Gtk.CheckButton;
  let endAfter: Gtk.CheckButton;
  let countSpin: Gtk.SpinButton;
  let cal: Gtk.Calendar;
  let untilLabel: Gtk.Label;

  const close = () => setRecurDialog(false);

  const spin = (max: number, set: (sb: Gtk.SpinButton) => void) =>
    (
      <Gtk.SpinButton
        class="recur-spin"
        numeric
        $={(sb: Gtk.SpinButton) => {
          sb.set_adjustment(Gtk.Adjustment.new(1, 1, max, 1, 1, 0));
          set(sb);
        }}
      />
    ) as Gtk.Widget;

  const fmtUntil = (g: GLib.DateTime) =>
    `${["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][g.get_day_of_week() % 7]} ${MON[g.get_month() - 1]} ${g.get_day_of_month()}`;

  const syncFreq = () =>
    weekRow.set_visible(FREQS[freqDrop.get_selected()] === "week");

  const seed = () => {
    const r = recurHolder.initial;
    freqDrop.set_selected(FREQS.indexOf(r?.freq ?? "week"));
    intervalSpin.set_value(r?.interval ?? 1);
    const wd = new Set(r?.weekdays ?? [recurHolder.date.getDay()]);
    dayBtns.forEach((b, i) => b.set_active(wd.has(i)));
    const e = r?.ends ?? { type: "never" };
    endNever.set_active(e.type === "never");
    endOn.set_active(e.type === "on");
    endAfter.set_active(e.type === "after");
    countSpin.set_value(e.count ?? 4);
    let until = e.until;
    if (!until) {
      const d = recurHolder.date;
      // 0-based month, matching done()/gwrite/recur.ts (GLib's 1-based API adds
      // the +1 back on display at select_day below).
      until = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    }
    const [y, m, d] = until.split("-").map(Number);
    cal.select_day(GLib.DateTime.new_local(y, m + 1, d, 0, 0, 0));
    syncFreq();
  };
  recurDialog.subscribe(() => recurDialog.get() && seed());

  const done = () => {
    const freq = FREQS[freqDrop.get_selected()];
    const r: Recur = { freq, interval: Math.round(intervalSpin.get_value()) };
    if (freq === "week")
      r.weekdays = dayBtns
        .map((b, i) => (b.get_active() ? i : -1))
        .filter((i) => i >= 0);
    if (recurHolder.initial?.monthByWeekday && freq === "month")
      r.monthByWeekday = true;
    if (endOn.get_active()) {
      const g = cal.get_date();
      r.ends = {
        type: "on",
        until: `${g.get_year()}-${g.get_month() - 1}-${g.get_day_of_month()}`,
      };
    } else if (endAfter.get_active()) {
      r.ends = { type: "after", count: Math.round(countSpin.get_value()) };
    } else r.ends = { type: "never" };
    recurHolder.apply(r);
    close();
  };

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) close();
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => {
        root = r;
        // Trap focus among the controls (no Enter override — Enter belongs to the
        // spin buttons); focus lands on the first field when it opens.
        modalFocusTrap(r, recurDialog, { panel: () => panel });
      }}
      visible={recurDialog((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="recur-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={C}
        valign={C}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={12}
      >
        <label class="dialog-title" label="Repeat" halign={Gtk.Align.START} />

        <box class="recur-line" spacing={8}>
          <label label="Every" />
          {spin(99, (sb) => (intervalSpin = sb))}
          <Gtk.DropDown
            class="recur-freq"
            $={(d: Gtk.DropDown) => {
              freqDrop = d;
              d.set_model(Gtk.StringList.new(FREQS));
              d.connect("notify::selected", syncFreq);
            }}
          />
        </box>

        <box class="recur-line" spacing={6} $={(b: Gtk.Box) => (weekRow = b)}>
          <label label="On" />
          {DOW2.map((d, i) => (
            <Gtk.ToggleButton
              class="day-toggle"
              $={(b: Gtk.ToggleButton) => (dayBtns[i] = b)}
            >
              <label label={d} />
            </Gtk.ToggleButton>
          ))}
        </box>

        <label class="recur-ends" label="Ends" halign={Gtk.Align.START} />
        <box class="recur-line" spacing={8}>
          <Gtk.CheckButton
            label="Never"
            $={(c: Gtk.CheckButton) => (endNever = c)}
          />
        </box>
        <box class="recur-line" spacing={8}>
          <Gtk.CheckButton
            label="On"
            $={(c: Gtk.CheckButton) => {
              endOn = c;
              c.set_group(endNever);
            }}
          />
          <menubutton class="recur-until">
            <label
              $={(l: Gtk.Label) => (untilLabel = l)}
              label="—"
              halign={Gtk.Align.START}
            />
            <popover>
              <Gtk.Calendar
                $={(c: Gtk.Calendar) => {
                  cal = c;
                  c.connect("day-selected", () => {
                    untilLabel.set_label(fmtUntil(c.get_date()));
                    endOn.set_active(true);
                  });
                }}
              />
            </popover>
          </menubutton>
        </box>
        <box class="recur-line" spacing={8}>
          <Gtk.CheckButton
            label="After"
            $={(c: Gtk.CheckButton) => {
              endAfter = c;
              c.set_group(endNever);
            }}
          />
          {spin(999, (sb) => {
            countSpin = sb;
            sb.connect("value-changed", () => endAfter.set_active(true));
          })}
          <label class="muted" label="times" />
        </box>

        <box class="dialog-actions" spacing={8}>
          <box hexpand />
          <button class="dialog-keep" onClicked={close}>
            <label label="Cancel" />
          </button>
          <button class="dialog-send" onClicked={done}>
            <label label="Done" />
          </button>
        </box>
      </box>
    </box>
  );
}
