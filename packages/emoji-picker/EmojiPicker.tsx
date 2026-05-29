import { createComputed, createState, For } from "ags";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import { execAsync } from "ags/process";
import GLib from "gi://GLib";
import { EMOJIS, EmojiRecord } from "./data";

// Each glyph is a real widget (FlowBox has no virtualization), and building
// them dominates launch time — so render only a small grid up front and lean on
// search to narrow the full set down. No scroll: results past what fits are
// dropped, which is what keeps both the initial paint and every keystroke snappy.
const COLUMNS = 10;
const ROWS = 4;
const MAX_RESULTS = COLUMNS * ROWS;

// Fixed cell + grid geometry. The grid area is pinned to exactly GRID_H (a
// ScrolledWindow with min==max content height) so the window never resizes as
// the result count changes — including the empty "No matches" state.
const CELL = 44;
const ROW_SPACING = 4;
const COL_SPACING = 4;
// 4 rows of cells + inter-row gaps, plus a little slack so a full grid never
// trips a scrollbar. min==max content height + propagateNaturalHeight on the
// ScrolledWindow pins this exactly (the pattern clipboard-picker uses).
const GRID_H = ROWS * CELL + (ROWS - 1) * ROW_SPACING + 12;

function close() {
  app.quit();
}

// Frecency: bump on pick, surface most-used first when the search box is empty.
// Snapshotted once at launch so the grid never reshuffles under the cursor.
const FRECENCY_PATH = `${GLib.get_user_cache_dir()}/emoji-picker-frecency.json`;
const decoder = new TextDecoder();

type Frecency = Record<string, { count: number; lastUsed: number }>;

function loadFrecency(): Frecency {
  try {
    const [ok, contents] = GLib.file_get_contents(FRECENCY_PATH);
    if (ok) return JSON.parse(decoder.decode(contents));
  } catch {
    // corrupt or missing cache — start fresh
  }
  return {};
}

function saveFrecency(data: Frecency) {
  try {
    GLib.file_set_contents(FRECENCY_PATH, JSON.stringify(data));
  } catch (err) {
    console.error("emoji-picker: frecency save failed", err);
  }
}

function frecencyScore(e: { count: number; lastUsed: number }): number {
  const ageDays = (Date.now() - e.lastUsed) / 86_400_000;
  return e.count / (1 + ageDays);
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

export default function EmojiPicker() {
  let contentbox: Gtk.Box;
  let searchentry: Gtk.Entry;
  let win: Astal.Window;

  const frecency = loadFrecency();
  const [query, setQuery] = createState("");

  // Default view (empty query): frecent first, then dataset order.
  const byFrecency = [...EMOJIS].sort(
    (a, b) =>
      (frecency[b.e] ? frecencyScore(frecency[b.e]) : 0) -
      (frecency[a.e] ? frecencyScore(frecency[a.e]) : 0),
  );

  const shown = createComputed(() => {
    const q = query().trim().toLowerCase();
    if (q === "") return byFrecency.slice(0, MAX_RESULTS);
    const terms = q.split(/\s+/);
    const matched = EMOJIS.filter((r) => {
      const h = haystack(r);
      return terms.every((t) => h.includes(t));
    });
    // Description prefix matches first, then frecency.
    matched.sort((a, b) => {
      const ap = a.d.toLowerCase().startsWith(q) ? 1 : 0;
      const bp = b.d.toLowerCase().startsWith(q) ? 1 : 0;
      if (ap !== bp) return bp - ap;
      const af = frecency[a.e] ? frecencyScore(frecency[a.e]) : 0;
      const bf = frecency[b.e] ? frecencyScore(frecency[b.e]) : 0;
      return bf - af;
    });
    return matched.slice(0, MAX_RESULTS);
  });

  async function pick(r: EmojiRecord) {
    const prev = frecency[r.e] ?? { count: 0, lastUsed: 0 };
    frecency[r.e] = { count: prev.count + 1, lastUsed: Date.now() };
    saveFrecency(frecency);
    // Put the glyph on the clipboard, then exit. Close only after wl-copy has
    // taken ownership of the selection, or quitting would race it away.
    try {
      await execAsync(["wl-copy", r.e]);
    } catch (err) {
      console.error("emoji-picker: copy failed", err);
    }
    close();
  }

  function pickTop() {
    const top = shown()[0];
    if (top) pick(top);
  }

  // Escape closes. Enter (handled on the entry) picks the first match.
  function onKey(_e: Gtk.EventControllerKey, keyval: number) {
    if (keyval === Gdk.KEY_Escape) {
      close();
      return true;
    }
    return false;
  }

  // Close on click outside the panel.
  function onClick(_e: Gtk.GestureClick, _: number, x: number, y: number) {
    const [, rect] = contentbox.compute_bounds(win);
    if (
      !(
        x >= rect.origin.x &&
        x <= rect.origin.x + rect.size.width &&
        y >= rect.origin.y &&
        y <= rect.origin.y + rect.size.height
      )
    ) {
      close();
      return true;
    }
  }

  return (
    <window
      $={(ref) => (win = ref)}
      name="emoji-picker"
      namespace="emoji-picker"
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (!visible) return;
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
          searchentry.grab_focus();
          return GLib.SOURCE_REMOVE;
        });
      }}
    >
      <Gtk.EventControllerKey onKeyPressed={onKey} />
      <Gtk.GestureClick onPressed={onClick} />
      <box
        $={(ref) => (contentbox = ref)}
        class="panel"
        valign={Gtk.Align.CENTER}
        halign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={12}
      >
        <entry
          $={(ref) => (searchentry = ref)}
          primaryIconName="system-search-symbolic"
          placeholderText="Search emoji…"
          onNotifyText={({ text }) => setQuery(text)}
          onActivate={pickTop}
        />
        <Gtk.Separator />
        <Gtk.ScrolledWindow
          minContentHeight={GRID_H}
          maxContentHeight={GRID_H}
          propagateNaturalHeight
        >
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
              halign={Gtk.Align.START}
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
    </window>
  );
}
