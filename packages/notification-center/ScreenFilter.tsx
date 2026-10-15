import { createState } from "ags";
import { Astal, Gtk } from "ags/gtk4";
import { execAsync } from "ags/process";
import GLib from "gi://GLib";

// Screen filter (night-light) control. Writes ONE GLSL shader with the exact
// warmth/brightness factors baked in as float literals and points Hyprland's
// `decoration:screen_shader` at it — continuous 0..100 values straight from the
// sliders, no pre-generated shader matrix and no hyprshade indirection. The
// neutral 0-warmth/100-brightness case (and the off switch) restores the
// compositor default via the special `[[EMPTY]]` value (what `hyprshade off`
// set under the hood). Two alternating files make Hyprland recompile when only
// the contents changed: re-applying the option with an unchanged path is
// early-returned, so each apply flips to the other slot.

// Black at 0; keep a usable floor on the brightness slider.
const MIN_BRIGHT = 10;
const NEUTRAL_WARMTH = 0;
const NEUTRAL_BRIGHT = 100;

const CACHE_DIR = `${GLib.get_user_cache_dir()}/screen-filter`;
const shaderPath = (slot: number) => `${CACHE_DIR}/filter-${slot}.glsl`;

// Hyprland's Lua config has no `hyprctl keyword`; options go through hl.config.
const setShader = (value: string) => [
  "hyprctl",
  "eval",
  `hl.config({ decoration = { screen_shader = ${JSON.stringify(value)} } })`,
];

const shaderSource = (warmth: number, bright: number) => `precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;
void main() {
    vec4 c = texture2D(tex, v_texcoord);
    float redFactor = ${(warmth / 100).toFixed(2)};
    vec3 redResult = mix(c.rgb, vec3(c.r, 0.0, 0.0), redFactor);
    vec3 linear = pow(redResult, vec3(2.2));
    linear *= ${(bright / 100).toFixed(2)};
    vec3 srgb = pow(linear, vec3(1.0/2.2));
    gl_FragColor = vec4(srgb, c.a);
}
`;

export default function ScreenFilter() {
  const [warmth, setWarmth] = createState(NEUTRAL_WARMTH);
  const [bright, setBright] = createState(NEUTRAL_BRIGHT);
  const [on, setOn] = createState(false);

  let warmthSlider: Astal.Slider;
  let brightSlider: Astal.Slider;

  // Seed from the live compositor option so reopening the center reflects the
  // shader that's actually applied (survives daemon restarts). Our own file
  // carries the factors as float literals — parse them back out.
  execAsync(["hyprctl", "getoption", "decoration:screen_shader", "-j"])
    .then((out) => {
      const str = JSON.parse(out).str as string;
      if (!str.startsWith(CACHE_DIR)) return;
      const [ok, bytes] = GLib.file_get_contents(str);
      if (!ok) return;
      const src = new TextDecoder().decode(bytes);
      const w = /redFactor = ([\d.]+);/.exec(src);
      const b = /linear \*= ([\d.]+);/.exec(src);
      if (!w || !b) return;
      // Set the handles first (updates state via value-changed while `on` is
      // still false, so it doesn't re-apply the already-live shader), then
      // flip on.
      warmthSlider.value = Math.round(parseFloat(w[1]) * 100);
      brightSlider.value = Math.max(
        MIN_BRIGHT,
        Math.round(parseFloat(b[1]) * 100),
      );
      setOn(true);
    })
    .catch(() => {});

  // Slider drags fire rapidly; coalesce to the latest pending change so we
  // write one shader per gesture rather than per pixel.
  let pending = 0;
  let slot = 0;
  const apply = (w: number, b: number, enabled: boolean) => {
    if (pending) GLib.source_remove(pending);
    pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
      pending = 0;
      const neutral = w === NEUTRAL_WARMTH && b === NEUTRAL_BRIGHT;
      const argv =
        !enabled || neutral
          ? setShader("[[EMPTY]]")
          : (() => {
              slot = 1 - slot;
              const path = shaderPath(slot);
              GLib.mkdir_with_parents(CACHE_DIR, 0o755);
              GLib.file_set_contents(path, shaderSource(w, b));
              return setShader(path);
            })();
      execAsync(argv).catch((err) =>
        console.error("notification-center: hyprctl screen_shader failed", err),
      );
      return GLib.SOURCE_REMOVE;
    });
  };

  const onWarmth = (v: number) => {
    const w = Math.round(v);
    if (w === warmth.get()) return;
    setWarmth(w);
    if (on.get()) apply(w, bright.get(), true);
  };
  const onBright = (v: number) => {
    const b = Math.max(MIN_BRIGHT, Math.round(v));
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
        {/* Continuous 0..100: set_round_digits(0) snaps the handle to whole
            percents and we read the committed value from value-changed. No
            reactive `value` binding — that fights GTK's own drag handler,
            which is what moves the handle. */}
        <slider
          $={(r) => {
            warmthSlider = r;
            r.set_round_digits(0);
            r.value = NEUTRAL_WARMTH;
            r.connect("value-changed", () => onWarmth(r.value));
          }}
          min={0}
          max={100}
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
            r.value = NEUTRAL_BRIGHT;
            r.connect("value-changed", () => onBright(r.value));
          }}
          min={MIN_BRIGHT}
          max={100}
          step={1}
        />
      </box>
    </box>
  ) as Gtk.Widget;
}
