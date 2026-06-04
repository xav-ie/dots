import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { exec, subprocess } from "ags/process";
import { writeFile } from "ags/file";
import GLib from "gi://GLib";

// Live microphone visualizer for the virtual headset mic. AstalCava only
// watches the default sink, and cava's pulse `source = auto` resolves to that
// sink's monitor (silent), so we pin cava to the Virtual_Headset_Mic source by
// name (falling back to the default source). The config is written to a tmp
// file at startup.
const BARS = 12;
// ascii_max_range: number of discrete levels - 1. Kept single-digit (<= 9) so
// each bar stays one character and the digit parser below holds.
const MAX = 9;
// Per-bar height = BASE + level * STEP; the row is pinned to the tallest
// possible bar so every bar shares a constant bottom baseline (rather than the
// row collapsing to the current max and drifting).
const BASE = 2;
const STEP = 2;
const MAX_HEIGHT = BASE + MAX * STEP;

// The pw-loopback node created by virtual-headset (see its pipewire.rs).
const VIRTUAL_HEADSET_SOURCE = "Virtual_Headset_Mic";

// cava's pulse input wants the source name, not "auto" (which would visualize
// speaker output). Prefer the virtual headset mic; fall back to the default
// source, then to auto. Snapshotted at startup.
function micSource(): string {
  try {
    const sources = exec(["pactl", "list", "sources", "short"]);
    if (sources.includes(VIRTUAL_HEADSET_SOURCE)) return VIRTUAL_HEADSET_SOURCE;
  } catch {
    // fall through to the default source
  }
  try {
    return exec(["pactl", "get-default-source"]).trim() || "auto";
  } catch {
    return "auto";
  }
}

function config(source: string): string {
  return `[general]
bars = ${BARS}
# autosens auto-scales gain so normal speech reaches the top of the range.
autosens = 1
overshoot = 20

[input]
method = pulse
source = ${source}

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = ${MAX}
# Semicolon, not NUL: AGS's line reader treats a NUL byte as a string
# terminator, which would truncate every frame to its first digit.
bar_delimiter = 59
channels = mono

[smoothing]
# Lower noise_reduction = snappier, more sensitive response (default ~0.77).
noise_reduction = 0.25
`;
}

export default function CavaMic() {
  const [levels, setLevels] = createState<number[]>(new Array(BARS).fill(0));

  const configPath = `${GLib.get_tmp_dir()}/bar-cava-mic.conf`;
  writeFile(configPath, config(micSource()));

  const proc = subprocess(
    ["cava", "-p", configPath],
    (line) => {
      // Each frame is BARS single digits (0..MAX) separated by semicolons.
      const digits = line.replace(/[^0-9]/g, "");
      if (digits.length < BARS) return;
      setLevels(
        digits
          .slice(0, BARS)
          .split("")
          .map((c) => Number(c)),
      );
    },
    (err) => console.error("bar: cava", err),
  );
  onCleanup(() => proc.kill());

  // Each bar is a fixed-height column: a vexpand spacer on top pushes the
  // colored cell to the bottom, so every bar shares the same baseline and only
  // grows upward — independent of how tall the loudest bar gets.
  return (
    <box class="module cava" valign={Gtk.Align.END}>
      {Array.from({ length: BARS }, (_, i) => (
        <box
          class="cava-col"
          orientation={Gtk.Orientation.VERTICAL}
          heightRequest={MAX_HEIGHT}
        >
          <box vexpand />
          <box
            class="cava-bar"
            heightRequest={levels((l) => BASE + (l[i] ?? 0) * STEP)}
          />
        </box>
      ))}
    </box>
  ) as Gtk.Widget;
}
