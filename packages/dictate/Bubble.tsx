import { Astal, Gtk } from "ags/gtk4";
import cairo from "cairo";
import GLib from "gi://GLib";
import Pango from "gi://Pango";
import { label, phase, shape } from "./session";

const { BOTTOM } = Astal.WindowAnchor;

// Transcript width and height in lines while holding; resize and scroll
// animation length.
const WIDE = 560;
const LINES = 3;
const ANIM_MS = 200;
// The fixed, transparent surface the bubble animates inside; roomy enough for
// the three-line box.
const FRAME_WIDTH = WIDE + 120;
const FRAME_HEIGHT = 160;

const easeOut = (t: number) => 1 - (1 - t) ** 3;

// Top of each laid-out line in pixels, plus the bottom of the last one.
function lineTops(layout: Pango.Layout): number[] {
  const tops: number[] = [];
  const iter = layout.get_iter();
  do tops.push(iter.get_line_extents()[1].y / Pango.SCALE);
  while (iter.next_line());
  tops.push(layout.get_extents()[1].height / Pango.SCALE);
  return tops;
}

// Eases `apply` from `read()` to a target on the widget's frame clock. A
// repeated target is ignored, so re-layouts mid-animation don't restart it;
// while the widget is unmapped it jumps straight there.
function animator(
  widget: Gtk.Widget,
  read: () => number[],
  apply: (values: number[]) => void,
) {
  let tick = 0;
  let start = 0;
  let from: number[] = [];
  let to: number[] = [];
  return (target: number[]) => {
    if (target.every((v, i) => v === to[i])) return;
    to = target;
    if (!widget.get_mapped()) {
      if (tick) widget.remove_tick_callback(tick);
      tick = 0;
      apply(to);
      return;
    }
    from = read();
    start = GLib.get_monotonic_time();
    if (tick) return;
    tick = widget.add_tick_callback((_w, clock) => {
      const t = Math.min(
        1,
        (clock.get_frame_time() - start) / (ANIM_MS * 1000),
      );
      apply(from.map((f, i) => f + (to[i] - f) * easeOut(t)));
      if (t < 1) return GLib.SOURCE_CONTINUE;
      tick = 0;
      return GLib.SOURCE_REMOVE;
    });
  };
}

// The dictation bubble, flush with the bottom edge. A press shows it at pill
// height and transcript width; once the gesture is known it animates to the
// three-line transcript (hold) or shrinks to the status pill (tap). Only the
// bubble animates: resizing the layer surface every frame makes Hyprland
// stretch the stale buffer, so the surface stays a fixed transparent frame
// with an empty input region (clicks go through). It never takes keyboard
// focus, so text lands in the window you're dictating to.
export default function Bubble() {
  let text: Gtk.Label;

  return (
    <window
      name="dictate"
      namespace="dictate"
      anchor={BOTTOM}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.NONE}
      visible={phase((p) => p !== "idle")}
      $={(win) =>
        win.connect("map", () =>
          win.get_surface()?.set_input_region(new cairo.Region()),
        )
      }
    >
      <box widthRequest={FRAME_WIDTH} heightRequest={FRAME_HEIGHT}>
        <box
          class={phase((p) => `bubble ${p}`)}
          spacing={12}
          halign={Gtk.Align.CENTER}
          valign={Gtk.Align.END}
          hexpand
          vexpand
        >
          <box class="dot" valign={Gtk.Align.START} />
          {/* Holding, the text fills from the top; once full, new lines push
            older ones up and out, always landing on a line boundary. */}
          <Gtk.ScrolledWindow
            class="transcript"
            hscrollbarPolicy={Gtk.PolicyType.NEVER}
            vscrollbarPolicy={Gtk.PolicyType.EXTERNAL}
            $={(sw) => {
              const adj = sw.get_vadjustment();
              const resize = animator(
                sw,
                () => sw.get_size_request(),
                ([w, h]) => sw.set_size_request(Math.round(w), Math.round(h)),
              );
              const scroll = animator(
                sw,
                () => [adj.get_value()],
                ([v]) => adj.set_value(v),
              );
              const update = () => {
                const tops = lineTops(text.get_layout());
                const lines = tops.length - 1;
                const lineHeight = tops[1] - tops[0];
                if (shape.get() === "hold") {
                  resize([
                    WIDE,
                    Math.ceil(
                      lines >= LINES
                        ? tops[LINES] - tops[0]
                        : lineHeight * LINES,
                    ),
                  ]);
                  scroll([lines > LINES ? tops[lines - LINES] : 0]);
                } else {
                  const [textWidth] = text
                    .create_pango_layout(text.get_label())
                    .get_pixel_size();
                  const pill = shape.get() === "pill";
                  resize([pill ? textWidth + 1 : WIDE, Math.ceil(lineHeight)]);
                  scroll([0]);
                }
              };
              shape.subscribe(update);
              label.subscribe(update);
              adj.connect("notify::upper", update);
              // Size it before the first show.
              GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                update();
                return GLib.SOURCE_REMOVE;
              });
            }}
          >
            <label
              $={(ref) => (text = ref)}
              class="text"
              label={label}
              wrap
              xalign={0}
              yalign={0}
              valign={Gtk.Align.START}
            />
          </Gtk.ScrolledWindow>
        </box>
      </box>
    </window>
  ) as Gtk.Window;
}
