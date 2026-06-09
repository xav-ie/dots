import { Gtk } from "ags/gtk4";
import Pango from "gi://Pango";
import GLib from "gi://GLib";
import { createState, For } from "ags";
import { execAsync } from "ags/process";

// Today + tomorrow forecast from wttr.in (no API key; location auto-detected by
// IP). Refreshed on load and every 30 minutes.

interface Day {
  label: string;
  icon: string;
  hi: string;
  lo: string;
  desc: string;
  rain: string;
}

// wttr.in WWO weatherCode → Adwaita symbolic weather icon.
function codeIcon(code?: string): string {
  const c = Number(code ?? 0);
  if (c === 113) return "weather-clear-symbolic";
  if (c === 116) return "weather-few-clouds-symbolic";
  if (c === 119 || c === 122) return "weather-overcast-symbolic";
  if ([143, 248, 260].includes(c)) return "weather-fog-symbolic";
  if ([200, 386, 389, 392, 395].includes(c)) return "weather-storm-symbolic";
  if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371].includes(c))
    return "weather-snow-symbolic";
  if (c >= 176) return "weather-showers-symbolic";
  return "weather-few-clouds-symbolic";
}

const [days, setDays] = createState(new Array<Day>());

function refresh(): void {
  execAsync(["curl", "-fsS", "-m", "10", "https://wttr.in/Boston?format=j1"])
    .then((out) => {
      const j = JSON.parse(out);
      const w = j.weather ?? [];
      const cur = j.current_condition?.[0];
      // The ~midday hourly entry (3-hourly → index 4 ≈ 12:00) is a representative
      // icon/description for the day; today uses the live current condition.
      const mk = (d: any, label: string, live = false): Day => {
        const mid = d.hourly?.[4];
        const src = live ? cur : mid;
        // Highest chance of rain across the day's 3-hourly forecast.
        const rain = (d.hourly ?? []).reduce(
          (m: number, h: any) => Math.max(m, Number(h.chanceofrain) || 0),
          0,
        );
        return {
          label,
          icon: codeIcon(src?.weatherCode),
          hi: `${d.maxtempF}°`,
          lo: `${d.mintempF}°`,
          desc: src?.weatherDesc?.[0]?.value ?? "",
          rain: `${rain}%`,
        };
      };
      const next: Day[] = [];
      if (w[0]) next.push(mk(w[0], "Today", true));
      if (w[1]) next.push(mk(w[1], "Tomorrow"));
      setDays(next);
    })
    .catch((e) => console.error("notification-center: weather fetch", e));
}

refresh();
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1800, () => {
  refresh();
  return GLib.SOURCE_CONTINUE;
});

function DayCard({ d }: { d: Day }) {
  return (
    <box class="weather-day" orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <label class="weather-label" label={d.label} halign={Gtk.Align.START} />
      <box spacing={10}>
        <image iconName={d.icon} pixelSize={40} valign={Gtk.Align.CENTER} />
        <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
          <label class="weather-hi" label={d.hi} halign={Gtk.Align.START} />
          <label class="weather-lo" label={d.lo} halign={Gtk.Align.START} />
        </box>
      </box>
      <label
        class="weather-desc"
        label={d.desc}
        halign={Gtk.Align.START}
        ellipsize={Pango.EllipsizeMode.END}
      />
      {/* Rain chance on its own last line, under the condition text. */}
      <box class="weather-rain" spacing={3} halign={Gtk.Align.START}>
        <image iconName="weather-showers-symbolic" pixelSize={14} />
        <label label={d.rain} />
      </box>
    </box>
  );
}

// Today + tomorrow cards. Rendered as one homogeneous block (two equal cards)
// that the center pairs with the screen-filter card in a 50/50 row. Always
// visible so its half holds its place even before the forecast loads.
export default function Weather() {
  return (
    <box class="weather" spacing={12} homogeneous>
      <For each={days}>{(d) => <DayCard d={d} />}</For>
    </box>
  );
}
