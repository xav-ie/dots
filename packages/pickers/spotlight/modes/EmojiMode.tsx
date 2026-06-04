import { createComputed, createState, For } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import { EMOJIS, EmojiRecord } from "./data";
import { frecencyStore } from "../../lib/frecency";
import { ModeProps, PANEL_CONTENT_H } from "./types";

const COLUMNS = 6;
// Bigger cells (≈ double the old 44px) that stretch to fill the panel width; the
// grid scrolls past what fits the shared panel height.
const MAX_RESULTS = 48;
const CELL = 84;
const ROW_SPACING = 6;
const COL_SPACING = 6;

// Put text on the Wayland clipboard. Deliberately STDIN-only: wl-copy forks a
// daemon that holds any piped stdout/stderr open to serve the selection, so a
// communicate that pipes either waits forever for EOF (Enter would need a second
// press). Piping only stdin resolves as soon as the foreground wl-copy exits.
function copyText(text: string): Promise<void> {
  const proc = Gio.Subprocess.new(["wl-copy"], Gio.SubprocessFlags.STDIN_PIPE);
  const stdin = new GLib.Bytes(new TextEncoder().encode(text));
  return new Promise((resolve, reject) => {
    proc.communicate_async(stdin, null, (_, res) => {
      try {
        proc.communicate_finish(res);
        if (proc.get_successful()) resolve();
        else reject(new Error("spotlight/emoji: wl-copy failed"));
      } catch (err) {
        reject(err);
      }
    });
  });
}

// Lowercased searchable text per record, built once.
const haystacks = new Map<EmojiRecord, string>();
function haystack(r: EmojiRecord): string {
  let h = haystacks.get(r);
  if (h === undefined) {
    h = `${r.d} ${r.a.join(" ")} ${r.t.join(" ")} ${r.c}`.toLowerCase();
    haystacks.set(r, h);
  }
  return h;
}

export default function EmojiMode({ register, close, getWin }: ModeProps) {
  let searchentry: Gtk.Entry;

  const fr = frecencyStore("emoji");
  const [query, setQuery] = createState("");
  // Default-view ordering (frecent first). Recomputed on each show so a pick
  // from a previous open is reflected (the instance is resident).
  const [byFrecency, setByFrecency] =
    createState<EmojiRecord[]>(orderByFrecency());

  function orderByFrecency(): EmojiRecord[] {
    const frecency = fr.load();
    return [...EMOJIS].sort(
      (a, b) => fr.score(frecency, b.e) - fr.score(frecency, a.e),
    );
  }

  const shown = createComputed(() => {
    const q = query().trim().toLowerCase();
    if (q === "") return byFrecency().slice(0, MAX_RESULTS);
    const frecency = fr.load();
    const terms = q.split(/\s+/);
    const matched = EMOJIS.filter((r) => {
      const h = haystack(r);
      return terms.every((t) => h.includes(t));
    });
    matched.sort((a, b) => {
      const ap = a.d.toLowerCase().startsWith(q) ? 1 : 0;
      const bp = b.d.toLowerCase().startsWith(q) ? 1 : 0;
      if (ap !== bp) return bp - ap;
      return fr.score(frecency, b.e) - fr.score(frecency, a.e);
    });
    return matched.slice(0, MAX_RESULTS);
  });

  async function pick(r: EmojiRecord) {
    fr.bump(r.e);
    try {
      await copyText(r.e);
    } catch (err) {
      console.error("spotlight/emoji: copy failed", err);
    }
    close();
  }

  function pickTop() {
    const top = shown()[0];
    if (top) pick(top);
  }

  function onShow() {
    setQuery("");
    searchentry.set_text("");
    setByFrecency(orderByFrecency());
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      searchentry.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  function onKey(keyval: number) {
    if (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter) {
      // Enter reaches here only when the entry hasn't taken focus yet (a fast
      // open). If a glyph holds focus instead, let it activate that glyph.
      const focus = getWin()?.get_focus() ?? null;
      if (focus && focus !== searchentry && !focus.is_ancestor(searchentry)) {
        return false;
      }
      pickTop();
      return true;
    }
    return false;
  }

  register({ onShow, focus: () => searchentry.grab_focus(), onKey });

  return (
    <box
      class="mode mode-emoji"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
      heightRequest={PANEL_CONTENT_H}
    >
      <entry
        $={(ref) => (searchentry = ref)}
        primaryIconName="system-search-symbolic"
        placeholderText="Search emoji…"
        onNotifyText={({ text }) => setQuery(text)}
        onActivate={pickTop}
      />
      <Gtk.Separator />
      <Gtk.ScrolledWindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
        <box orientation={Gtk.Orientation.VERTICAL}>
          <label
            class="dim"
            label="No matches."
            visible={shown((s) => s.length === 0)}
          />
          <Gtk.FlowBox
            class="grid"
            selectionMode={Gtk.SelectionMode.NONE}
            homogeneous
            maxChildrenPerLine={COLUMNS}
            minChildrenPerLine={COLUMNS}
            rowSpacing={ROW_SPACING}
            columnSpacing={COL_SPACING}
            valign={Gtk.Align.START}
            halign={Gtk.Align.FILL}
          >
            <For each={shown}>
              {(r: EmojiRecord) => (
                <button
                  class="emoji"
                  tooltipText={r.d}
                  widthRequest={CELL}
                  heightRequest={CELL}
                  onClicked={() => pick(r)}
                >
                  <label label={r.e} />
                </button>
              )}
            </For>
          </Gtk.FlowBox>
        </box>
      </Gtk.ScrolledWindow>
    </box>
  );
}
