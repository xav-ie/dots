import { createComputed, createEffect, createState, For, onCleanup } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import { EMOJIS, EmojiRecord } from "./data";
import { frecencyStore } from "../../lib/frecency";
import { createSelection, scrollIntoView } from "../../lib/selection";
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

export default function EmojiMode({ register, close }: ModeProps) {
  let searchentry: Gtk.Entry;
  let scroller: Gtk.ScrolledWindow;
  let listBox: Gtk.Box;

  const fr = frecencyStore("emoji");
  const [query, setQuery] = createState("");
  // Cell button per glyph, so the selection can scroll the highlighted emoji
  // into view as the arrows walk the grid.
  const cellButtons = new Map<string, Gtk.Button>();
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

  const sel = createSelection(shown);

  // Keep the highlighted glyph visible as the arrows walk the grid (or as a new
  // query resets it to the top).
  createEffect(() => {
    const item = sel.current();
    if (!item) return;
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      scrollIntoView(scroller, listBox, cellButtons.get(item.e));
      return GLib.SOURCE_REMOVE;
    });
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

  function onShow() {
    setQuery("");
    searchentry.set_text("");
    setByFrecency(orderByFrecency());
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      searchentry.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Grid navigation. Focus stays on the entry, so the arrows must be caught in
  // the CAPTURE phase (below) — otherwise the entry eats Left/Right as cursor
  // moves before we get a look. Left/Right step one glyph; Up/Down jump a row.
  function onNavKey(keyval: number, modk: number) {
    // Ctrl+←/→ is the shell's mode cycle (handled higher up); leave it alone.
    if ((modk & Gdk.ModifierType.CONTROL_MASK) !== 0) return false;
    if (keyval === Gdk.KEY_Left) {
      sel.move(-1);
      return true;
    }
    if (keyval === Gdk.KEY_Right) {
      sel.move(1);
      return true;
    }
    if (keyval === Gdk.KEY_Up) {
      sel.move(-COLUMNS);
      return true;
    }
    if (keyval === Gdk.KEY_Down) {
      sel.move(COLUMNS);
      return true;
    }
    return false;
  }

  // Enter is the entry's default action (onActivate → pick the highlight); the
  // arrows are consumed in CAPTURE, so nothing is left for the bubble handler.
  register({
    onShow,
    focus: () => searchentry.grab_focus(),
    onKey: () => false,
  });

  return (
    <box
      class="mode mode-emoji"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
      heightRequest={PANEL_CONTENT_H}
    >
      <Gtk.EventControllerKey
        propagationPhase={Gtk.PropagationPhase.CAPTURE}
        onKeyPressed={(_c, keyval, _k, modk) => onNavKey(keyval, modk)}
      />
      <entry
        $={(ref) => (searchentry = ref)}
        primaryIconName="system-search-symbolic"
        placeholderText="Search emoji…"
        onNotifyText={({ text }) => setQuery(text)}
        onActivate={() => {
          const top = sel.current();
          if (top) pick(top);
        }}
      />
      <Gtk.Separator />
      <Gtk.ScrolledWindow
        $={(ref) => (scroller = ref)}
        vexpand
        hscrollbarPolicy={Gtk.PolicyType.NEVER}
      >
        <box
          $={(ref) => (listBox = ref)}
          orientation={Gtk.Orientation.VERTICAL}
        >
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
              {(r: EmojiRecord) => {
                onCleanup(() => cellButtons.delete(r.e));
                return (
                  <button
                    class={sel.cls(r, "emoji")}
                    tooltipText={r.d}
                    widthRequest={CELL}
                    heightRequest={CELL}
                    onClicked={() => pick(r)}
                    $={(ref) => cellButtons.set(r.e, ref as Gtk.Button)}
                  >
                    <label label={r.e} />
                  </button>
                );
              }}
            </For>
          </Gtk.FlowBox>
        </box>
      </Gtk.ScrolledWindow>
    </box>
  );
}
