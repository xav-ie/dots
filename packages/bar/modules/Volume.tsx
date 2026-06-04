import { createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { execAsync } from "ags/process";
import AstalWp from "gi://AstalWp";

// Default-speaker volume + mute, fed by AstalWireplumber. Scroll adjusts
// volume, left-click opens pavucontrol, right-click toggles mute.
const STEP = 0.05;

export default function Volume() {
  const wp = AstalWp.get_default()!;
  const audio = wp.audio;

  const read = () => {
    const s = audio.defaultSpeaker;
    return {
      volume: s?.volume ?? 0,
      mute: s?.mute ?? true,
      icon: s?.volumeIcon || "audio-volume-muted-symbolic",
    };
  };

  const [state, setState] = createState(read());

  // Re-subscribe to the speaker's notify when the default sink changes, so the
  // bar keeps tracking volume/mute across device switches.
  let speaker: AstalWp.Endpoint | null = null;
  let speakerId = 0;
  const rebind = () => {
    if (speaker && speakerId) speaker.disconnect(speakerId);
    speaker = audio.defaultSpeaker;
    speakerId = speaker?.connect("notify", () => setState(read())) ?? 0;
    setState(read());
  };
  const audioId = audio.connect("notify::default-speaker", rebind);
  rebind();
  onCleanup(() => {
    audio.disconnect(audioId);
    if (speaker && speakerId) speaker.disconnect(speakerId);
  });

  const setVolume = (delta: number) => {
    const s = audio.defaultSpeaker;
    if (!s) return;
    s.volume = Math.max(0, Math.min(1.5, s.volume + delta));
    s.mute = false;
  };

  return (
    <box class={state((s) => `module volume${s.mute ? " muted" : ""}`)}>
      <Gtk.EventControllerScroll
        flags={Gtk.EventControllerScrollFlags.VERTICAL}
        onScroll={(_e, _dx, dy) => {
          // Natural scrolling: up (dy<0) raises volume.
          setVolume(dy < 0 ? STEP : -STEP);
          return true;
        }}
      />
      <button
        tooltipText="Scroll to adjust · click for mixer · right-click to mute"
        onClicked={() =>
          execAsync(["pavucontrol"]).catch((err) =>
            console.error("bar: pavucontrol failed", err),
          )
        }
      >
        <Gtk.GestureClick
          button={3 /* right */}
          onPressed={() => {
            const s = audio.defaultSpeaker;
            if (s) s.mute = !s.mute;
          }}
        />
        <box spacing={4}>
          <image iconName={state((s) => s.icon)} pixelSize={16} />
          <label label={state((s) => `${Math.round(s.volume * 100)}%`)} />
        </box>
      </button>
    </box>
  ) as Gtk.Widget;
}
