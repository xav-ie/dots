import { Gtk } from "ags/gtk4";
import Gdk from "gi://Gdk?version=4.0";
import GLib from "gi://GLib";
import Pango from "gi://Pango";
import AstalMpris from "gi://AstalMpris";
import { createBinding, createState, onCleanup, For } from "ags";

const mpris = AstalMpris.get_default();

// Art is a fixed-height strip whose width follows the image's aspect ratio, so a
// rectangular cover isn't cropped to a square — capped at 3× to keep panoramic
// art from dominating the card.
const ART_H = 120;
const ART_MAX_W = ART_H * 3;

interface Art {
  css: string;
  w: number;
}

function toPath(uri?: string | null): string | null {
  if (!uri) return null;
  if (uri.startsWith("file://")) {
    try {
      return GLib.filename_from_uri(uri)[0];
    } catch {
      return null;
    }
  }
  return uri;
}

// coverArt notifies on every metadata tick (position, etc.), so resolve each art
// file's CSS + aspect-fitted width once. Rendered as a background-image (which,
// unlike Gtk.Picture, contributes no natural size) on a box of that exact size.
const artCache = new Map<string, Art | null>();
function artInfo(path?: string | null): Art | null {
  const p = toPath(path);
  if (!p || !GLib.file_test(p, GLib.FileTest.EXISTS)) return null;
  if (artCache.has(p)) return artCache.get(p)!;
  let info: Art | null = null;
  try {
    const tex = Gdk.Texture.new_from_filename(p);
    const ratio = tex.get_width() / tex.get_height();
    const w = Math.max(ART_H, Math.min(ART_MAX_W, Math.round(ART_H * ratio)));
    info = {
      css: `background-image: url("file://${p}"); background-size: cover; background-position: center;`,
      w,
    };
  } catch {
    info = null;
  }
  artCache.set(p, info);
  return info;
}

function Player({ player }: { player: AstalMpris.Player }) {
  const title = createBinding(player, "title");
  const artist = createBinding(player, "artist");
  const status = createBinding(player, "playbackStatus");

  // coverArt briefly goes empty while AstalMpris re-downloads the file, and on a
  // track change the new file lags the title. Keep the last good art until a new
  // one actually resolves so the card never blanks or changes height — only its
  // width adjusts to the next cover's aspect ratio.
  const [art, setArt] = createState<Art | null>(artInfo(player.coverArt));
  const coverId = player.connect("notify::cover-art", () => {
    const info = artInfo(player.coverArt);
    if (info) setArt(info);
  });
  onCleanup(() => player.disconnect(coverId));

  const playIcon = status((s) =>
    s === AstalMpris.PlaybackStatus.PLAYING
      ? "media-playback-pause-symbolic"
      : "media-playback-start-symbolic",
  );

  return (
    <box class="mpris-player">
      <box
        class="mpris-content"
        orientation={Gtk.Orientation.VERTICAL}
        valign={Gtk.Align.CENTER}
        hexpand
      >
        <label
          class="mpris-title"
          halign={Gtk.Align.START}
          ellipsize={Pango.EllipsizeMode.END}
          label={title}
        />
        <label
          class="mpris-artist"
          halign={Gtk.Align.START}
          ellipsize={Pango.EllipsizeMode.END}
          label={artist}
        />
        <box class="mpris-controls" spacing={6} halign={Gtk.Align.START}>
          <button onClicked={() => player.previous()}>
            <image iconName="media-skip-backward-symbolic" />
          </button>
          <button onClicked={() => player.play_pause()}>
            <image iconName={playIcon} />
          </button>
          <button onClicked={() => player.next()}>
            <image iconName="media-skip-forward-symbolic" />
          </button>
        </box>
      </box>
      {/* Album art on the right: fixed height, aspect-ratio width. A
          background-image carries no natural size, so it never drives the card
          height; the width follows the cover's ratio (capped at 3×). */}
      <box
        class="mpris-art"
        valign={Gtk.Align.CENTER}
        halign={Gtk.Align.END}
        heightRequest={ART_H}
        widthRequest={art((a) => a?.w ?? ART_H)}
        visible={art((a) => a !== null)}
        css={art((a) => a?.css ?? "")}
      />
    </box>
  );
}

// MPRIS media widget at the top of the control center. Bound to the first
// available player; hidden entirely when nothing is playing.
export default function Mpris() {
  const players = createBinding(mpris, "players");
  return (
    <box
      class="mpris"
      orientation={Gtk.Orientation.VERTICAL}
      visible={players((p) => p.length > 0)}
    >
      <For each={players((p) => p.slice(0, 1))}>
        {(player) => <Player player={player} />}
      </For>
    </box>
  );
}
