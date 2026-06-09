import { Astal, Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import AstalWp from "gi://AstalWp";
import { createState } from "ags";

// Transient on-screen display for system volume. A single window anchored
// top-center that flashes the speaker level whenever the default sink's volume
// or mute changes (volume keys, wpctl, mixer, …) and fades out after a short
// idle. wireplumber's notify fires only on real changes, so the daemon never
// flashes one at startup.

const { TOP } = Astal.WindowAnchor;
const HIDE_MS = 1500;
const ANIM_MS = 220;

const [shown, setShown] = createState(false);
const [revealed, setRevealed] = createState(false);
const [level, setLevel] = createState(0); // 0..1
const [icon, setIcon] = createState("audio-volume-medium-symbolic");
const [muted, setMuted] = createState(false);

let hideTimer = 0;
function flash(): void {
  setShown(true);
  // Reveal on the next tick so the revealer starts collapsed and animates in.
  GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
    setRevealed(true);
    return GLib.SOURCE_REMOVE;
  });
  if (hideTimer) GLib.source_remove(hideTimer);
  hideTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HIDE_MS, () => {
    hideTimer = 0;
    setRevealed(false);
    // Drop the window only after the fade-out finishes.
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, ANIM_MS, () => {
      if (!revealed.get()) setShown(false);
      return GLib.SOURCE_REMOVE;
    });
    return GLib.SOURCE_REMOVE;
  });
}

const wp = AstalWp.get_default();
if (wp) {
  const audio = wp.audio;
  const update = (): void => {
    const s = audio.defaultSpeaker;
    if (!s) return;
    setLevel(Math.max(0, Math.min(1, s.volume)));
    setMuted(s.mute);
    setIcon(
      s.mute
        ? "audio-volume-muted-symbolic"
        : s.volumeIcon || "audio-volume-medium-symbolic",
    );
  };

  // Re-subscribe to the speaker's volume/mute when the default sink changes.
  // These notifies fire only on actual changes, so connecting never self-flashes.
  let speaker: AstalWp.Endpoint | null = null;
  let volId = 0;
  let muteId = 0;
  const rebind = (): void => {
    if (speaker) {
      if (volId) speaker.disconnect(volId);
      if (muteId) speaker.disconnect(muteId);
    }
    speaker = audio.defaultSpeaker;
    volId =
      speaker?.connect("notify::volume", () => {
        update();
        flash();
      }) ?? 0;
    muteId =
      speaker?.connect("notify::mute", () => {
        update();
        flash();
      }) ?? 0;
    update();
  };
  audio.connect("notify::default-speaker", rebind);
  rebind();
}

// One window, created once in app.ts. Top-anchored and (only TOP set) centered
// horizontally, so it floats in the bar's transparent middle gap. IGNORE +
// OVERLAY keep it from being pushed below the bar and put it above it; marginTop
// matches the bar's top margin (style.scss .bar) and the card is already the
// pill height (36px), so it lines up like a centre bar module. NONE keymode
// keeps it from ever stealing keyboard focus.
export default function Osd() {
  return (
    <window
      name="osd"
      namespace="osd"
      anchor={TOP}
      marginTop={6}
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.NONE}
      visible={shown}
    >
      <Gtk.Revealer
        transitionType={Gtk.RevealerTransitionType.CROSSFADE}
        transitionDuration={ANIM_MS}
        revealChild={revealed}
      >
        <box
          class={muted((m) => `osd${m ? " muted" : ""}`)}
          widthRequest={280}
          spacing={10}
          valign={Gtk.Align.CENTER}
        >
          <image iconName={icon} pixelSize={16} />
          {/* A real slider (not a levelbar) so it's the same widget/style as the
              notification-center sliders, but purely a readout: canTarget=false
              blocks pointer dragging (without dimming, unlike sensitive=false)
              and focusable=false keeps it out of focus. hexpand fills the width
              between the icon and the % readout. */}
          <slider
            class="osd-bar"
            hexpand
            min={0}
            max={1}
            value={level}
            canTarget={false}
            focusable={false}
          />
          <label
            class="osd-pct"
            label={level((l) => `${Math.round(l * 100)}%`)}
          />
        </box>
      </Gtk.Revealer>
    </window>
  ) as Gtk.Window;
}
