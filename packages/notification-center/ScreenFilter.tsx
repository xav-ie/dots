import { createState } from "ags";
import { Astal, Gtk } from "ags/gtk4";
import { execAsync } from "ags/process";
import GLib from "gi://GLib";

// Screen filter (night-light) control wired to hyprshade. The home-manager
// hyprshade module generates a matrix of GLSL shaders named
// `{warmth}-red-{brightness}.glsl` for warmth/brightness in steps of 10
// (0..100). This widget drives `hyprshade on <name>` from two sliders and
// `hyprshade off` at the neutral 0-red-100. State is seeded from
// `hyprshade current` so reopening the center reflects the live shader.

const STEP = 10;
const snap = (v: number) => Math.round(v / STEP) * STEP;
// `0-red-100` is the identity shader (no warmth, full brightness) → treat as off.
const NEUTRAL_WARMTH = 0;
const NEUTRAL_BRIGHT = 100;
// Black at 0; keep a usable floor on the brightness slider.
const MIN_BRIGHT = 10;

export default function ScreenFilter() {
  const [warmth, setWarmth] = createState(NEUTRAL_WARMTH);
  const [bright, setBright] = createState(NEUTRAL_BRIGHT);
  const [on, setOn] = createState(false);

  let warmthSlider: Astal.Slider;
  let brightSlider: Astal.Slider;

  execAsync(["hyprshade", "current"])
    .then((out) => {
      const m = /(\d+)-red-(\d+)/.exec(out.trim());
      if (!m) return;
      // Set the handles first (updates state via value-changed while `on` is
      // still false, so it doesn't re-apply the already-live shader), then flip on.
      warmthSlider.value = snap(+m[1]) / STEP;
      brightSlider.value = Math.max(MIN_BRIGHT, snap(+m[2])) / STEP;
      setOn(true);
    })
    .catch(() => {});

  // Slider drags fire rapidly; coalesce to the latest pending shader so we run
  // one `hyprshade` per gesture rather than per pixel.
  let pending = 0;
  const apply = (w: number, b: number, enabled: boolean) => {
    if (pending) GLib.source_remove(pending);
    pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
      pending = 0;
      const cmd =
        !enabled || (w === NEUTRAL_WARMTH && b === NEUTRAL_BRIGHT)
          ? ["hyprshade", "off"]
          : ["hyprshade", "on", `${w}-red-${b}`];
      execAsync(cmd).catch((err) =>
        console.error("notification-center: hyprshade failed", err),
      );
      return GLib.SOURCE_REMOVE;
    });
  };

  const onWarmth = (v: number) => {
    const w = snap(v);
    if (w === warmth.get()) return;
    setWarmth(w);
    if (on.get()) apply(w, bright.get(), true);
  };
  const onBright = (v: number) => {
    const b = Math.max(MIN_BRIGHT, snap(v));
    if (b === bright.get()) return;
    setBright(b);
    if (on.get()) apply(warmth.get(), b, true);
  };
  const toggle = (enabled: boolean) => {
    setOn(enabled);
    apply(warmth.get(), bright.get(), enabled);
  };

  return (
    <box
      class="screen-filter"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={8}
      hexpand
    >
      <box class="sf-header" spacing={8}>
        <image iconName="night-light-symbolic" pixelSize={16} />
        <label label="Screen Filter" halign={Gtk.Align.START} hexpand />
        <switch
          active={on}
          onNotifyActive={({ active }) => {
            if (active !== on.get()) toggle(active);
          }}
        />
      </box>
      <box class="sf-slider" orientation={Gtk.Orientation.VERTICAL}>
        <box class="sf-caption" spacing={6}>
          <label
            class="sf-name"
            label="Warmth"
            halign={Gtk.Align.START}
            hexpand
          />
          <label
            class="sf-pct"
            label={warmth((w) => `${w}%`)}
            halign={Gtk.Align.END}
          />
        </box>
        {/* Discrete 0..10 tens scale: set_round_digits(0) snaps the handle to
            whole ticks (each = 10%), and we read the committed value from
            value-changed. No reactive `value` binding — that fights GTK's own
            drag handler, which is what moves the handle. value*STEP is the 0..100
            value. */}
        <slider
          $={(r) => {
            warmthSlider = r;
            r.set_round_digits(0);
            r.value = NEUTRAL_WARMTH / STEP;
            r.connect("value-changed", () =>
              onWarmth(Math.round(r.value) * STEP),
            );
          }}
          min={0}
          max={100 / STEP}
          step={1}
        />
      </box>
      <box class="sf-slider" orientation={Gtk.Orientation.VERTICAL}>
        <box class="sf-caption" spacing={6}>
          <label
            class="sf-name"
            label="Brightness"
            halign={Gtk.Align.START}
            hexpand
          />
          <label
            class="sf-pct"
            label={bright((b) => `${b}%`)}
            halign={Gtk.Align.END}
          />
        </box>
        <slider
          $={(r) => {
            brightSlider = r;
            r.set_round_digits(0);
            r.value = NEUTRAL_BRIGHT / STEP;
            r.connect("value-changed", () =>
              onBright(Math.round(r.value) * STEP),
            );
          }}
          min={MIN_BRIGHT / STEP}
          max={100 / STEP}
          step={1}
        />
      </box>
    </box>
  ) as Gtk.Widget;
}
