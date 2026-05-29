import { createComputed, createState, For, onCleanup } from "ags";
import { Astal, Gtk, Gdk } from "ags/gtk4";
import app from "ags/gtk4/app";
import Graphene from "gi://Graphene";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import { ClipEntry, copy, decodeToFile, list, remove } from "./cliphist";

const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor;

// cliphist keeps up to 750 entries; a plain box in a ScrolledWindow renders
// every child eagerly (no virtualization), so building that many rows visibly
// stalls launch. Cap what we render — search still filters the full history,
// it just shows the first MAX_ROWS matches.
const MAX_ROWS = 50;

// Fixed thumbnail slot. Reserving it up front (min == max height) keeps the row
// from jumping when the decoded image swaps in for the placeholder icon.
const THUMB_W = 120;
const THUMB_H = 64;

// Hide rather than quit: the instance stays resident so the next open is
// instant (see app.ts). onNotifyVisible re-reads the clipboard on each show.
function close() {
  const win = app.get_window("clipboard-picker");
  if (win) win.visible = false;
}

// Temp dir for decoded image thumbnails, removed on quit. Decoded textures are
// cached by entry id so re-filtering (which tears down and rebuilds rows via
// <For>) never re-decodes the same image.
const THUMB_DIR = GLib.dir_make_tmp("clipboard-picker-XXXXXX");
const texCache = new Map<string, Gdk.Texture>();

function Thumbnail({ entry }: { entry: ClipEntry }) {
  const [tex, setTex] = createState<Gdk.Texture | null>(
    texCache.get(entry.id) ?? null,
  );

  if (!texCache.has(entry.id)) {
    const path = `${THUMB_DIR}/${entry.id}`;
    decodeToFile(entry, path)
      .then(() => {
        const texture = Gdk.Texture.new_from_filename(path);
        texCache.set(entry.id, texture);
        setTex(texture);
      })
      .catch((err) =>
        console.error("clipboard-picker: thumbnail decode failed", err),
      );
  }

  return (
    <box
      class="thumb"
      halign={Gtk.Align.START}
      valign={Gtk.Align.CENTER}
      heightRequest={THUMB_H}
      widthRequest={THUMB_W}
      overflow={Gtk.Overflow.HIDDEN}
    >
      <image
        iconName="image-x-generic-symbolic"
        pixelSize={28}
        hexpand
        halign={Gtk.Align.CENTER}
        visible={tex((t) => t === null)}
      />
      <Gtk.Picture
        contentFit={Gtk.ContentFit.CONTAIN}
        hexpand
        vexpand
        paintable={tex((t) => t)}
        visible={tex((t) => t !== null)}
      />
    </box>
  );
}

function ClipRow({
  entry,
  onDelete,
  registerButton,
}: {
  entry: ClipEntry;
  onDelete: () => void;
  registerButton: (button: Gtk.Button | null) => void;
}) {
  onCleanup(() => registerButton(null));
  return (
    <box class="row" spacing={6}>
      <button
        class="entry"
        hexpand
        $={(ref) => registerButton(ref as Gtk.Button)}
        onClicked={() => copy(entry).then(close)}
      >
        <box spacing={12}>
          {entry.isImage ? (
            <Thumbnail entry={entry} />
          ) : (
            <image iconName="edit-paste-symbolic" pixelSize={28} />
          )}
          <label
            label={entry.preview}
            halign={Gtk.Align.START}
            maxWidthChars={60}
            ellipsize={3 /* PANGO_ELLIPSIZE_END */}
          />
        </box>
      </button>
      <button class="delete" valign={Gtk.Align.CENTER} onClicked={onDelete}>
        <image iconName="user-trash-symbolic" pixelSize={20} />
      </button>
    </box>
  );
}

export default function ClipboardPicker() {
  let contentbox: Gtk.Box;
  let searchentry: Gtk.Entry;
  let win: Astal.Window;

  const [entries, setEntries] = createState(list());
  const [query, setQuery] = createState("");

  // Item (entry) buttons by id, so the arrow keys can step item-to-item and
  // skip the per-row trash buttons (which Tab still reaches normally).
  const itemButtons = new Map<string, Gtk.Button>();

  const shown = createComputed(() => {
    const q = query().trim().toLowerCase();
    const all = entries();
    const matched = q
      ? all.filter((e) => e.preview.toLowerCase().includes(q))
      : all;
    return matched.slice(0, MAX_ROWS);
  });

  onCleanup(() => {
    // Best-effort cleanup of decoded thumbnails; /tmp would reap them anyway.
    try {
      Gio.File.new_for_path(THUMB_DIR).trash(null);
    } catch {
      // ignore — not worth surfacing on shutdown
    }
  });

  function copyTop() {
    const top = shown()[0];
    if (top) copy(top).then(close);
  }

  function onDelete(entry: ClipEntry) {
    remove(entry).catch((err) =>
      console.error("clipboard-picker: delete failed", err),
    );
    setEntries(entries().filter((e) => e !== entry));
  }

  // True when keyboard focus is inside the search entry. GTK gives focus to the
  // entry's internal text node, not the entry itself, so we test ancestry.
  function searchHasFocus() {
    const focus = win.get_focus();
    return (
      focus !== null &&
      (focus === searchentry || focus.is_ancestor(searchentry))
    );
  }

  // The item buttons in current display order.
  function orderedItems(): Gtk.Button[] {
    return shown()
      .map((e) => itemButtons.get(e.id))
      .filter((b): b is Gtk.Button => b != null);
  }

  // Move focus prev/next between items (delta -1/+1), skipping trash buttons.
  // From the search box, Down enters the list; from the first item, Up returns
  // to the search box. A trash button (reached via Tab) counts as its own row.
  function focusItem(delta: number) {
    const items = orderedItems();
    if (items.length === 0) return;
    if (searchHasFocus()) {
      if (delta > 0) items[0].grab_focus();
      return;
    }
    const focus = win.get_focus();
    const cur = items.findIndex(
      (b) =>
        b === focus ||
        (focus !== null && b.get_parent() === focus.get_parent()),
    );
    if (cur === -1) {
      if (delta > 0) items[0].grab_focus();
      return;
    }
    const next = cur + delta;
    if (next < 0) searchentry.grab_focus();
    else if (next < items.length) items[next].grab_focus();
  }

  // Escape closes; Up/Down walk the focus chain between the search entry and the
  // rows (GTK only does this for Tab by default, so we translate the arrows).
  // Enter/Space activate the focused row. Any other key pressed while focus sits
  // in the list snaps back to the search box and is re-delivered there, so the
  // user can keep typing to filter without reaching for the mouse.
  function onKey(
    controller: Gtk.EventControllerKey,
    keyval: number,
    _: number,
    _mod: number,
  ) {
    if (keyval === Gdk.KEY_Escape) {
      close();
      return true;
    }
    if (keyval === Gdk.KEY_Down) {
      focusItem(1);
      return true;
    }
    if (keyval === Gdk.KEY_Up) {
      focusItem(-1);
      return true;
    }

    // Keys that must keep their normal in-list behaviour rather than snapping
    // back to search: Enter/Space activate the row; Tab/Shift+Tab traverse.
    const passthrough =
      keyval === Gdk.KEY_Return ||
      keyval === Gdk.KEY_KP_Enter ||
      keyval === Gdk.KEY_space ||
      keyval === Gdk.KEY_Tab ||
      keyval === Gdk.KEY_ISO_Left_Tab;
    if (!passthrough && !searchHasFocus()) {
      searchentry.grab_focus();
      controller.forward(searchentry);
      return true;
    }
    return false;
  }

  // Close on click outside the panel.
  function onClick(_e: Gtk.GestureClick, _: number, x: number, y: number) {
    const [, rect] = contentbox.compute_bounds(win);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) {
      close();
      return true;
    }
  }

  return (
    <window
      $={(ref) => (win = ref)}
      name="clipboard-picker"
      namespace="clipboard-picker"
      anchor={TOP | BOTTOM | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.EXCLUSIVE}
      onNotifyVisible={({ visible }) => {
        if (!visible) return;
        // Fresh state on every open: re-read the clipboard (it changes while
        // we're hidden), clear the previous search, and focus the entry. The
        // texCache survives, so already-seen thumbnails stay instant.
        searchentry.set_text("");
        setQuery("");
        setEntries(list());
        // Defer focus to idle so it wins over the focus GTK hands to the first
        // row on show — otherwise that row keeps its :focus ring.
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
        <box class="header" spacing={12}>
          <label class="title" label="Clipboard" halign={Gtk.Align.START} />
        </box>
        <entry
          $={(ref) => (searchentry = ref)}
          primaryIconName="system-search-symbolic"
          placeholderText="Search clipboard…"
          onNotifyText={({ text }) => setQuery(text)}
          onActivate={copyTop}
        />
        <Gtk.Separator />
        <Gtk.ScrolledWindow
          minContentHeight={460}
          maxContentHeight={460}
          propagateNaturalHeight
          hscrollbarPolicy={Gtk.PolicyType.NEVER}
        >
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <label
              class="dim"
              label={query((q) =>
                q ? "No matches." : "Clipboard history is empty.",
              )}
              visible={shown((s) => s.length === 0)}
            />
            <For each={shown}>
              {(entry) => (
                <ClipRow
                  entry={entry}
                  onDelete={() => onDelete(entry)}
                  registerButton={(btn) => {
                    if (btn) itemButtons.set(entry.id, btn);
                    else itemButtons.delete(entry.id);
                  }}
                />
              )}
            </For>
          </box>
        </Gtk.ScrolledWindow>
      </box>
    </window>
  );
}
