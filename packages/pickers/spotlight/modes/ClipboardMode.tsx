import { createComputed, createState, For, onCleanup } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import { ClipEntry, copy, decodeToFile, list, remove } from "./cliphist";
import { ModeProps, PANEL_CONTENT_H } from "./types";

// cliphist keeps up to 750 entries; a plain box renders every child eagerly, so
// cap what we build — search still filters the full history.
const MAX_ROWS = 50;

// Fixed thumbnail slot so a row doesn't jump when the image swaps in.
const THUMB_W = 120;
const THUMB_H = 64;

// Temp dir for decoded image thumbnails, removed on shutdown.
const THUMB_DIR = GLib.dir_make_tmp("spotlight-clipboard-XXXXXX");

// LRU cache of decoded textures keyed by entry id, so re-filtering never
// re-decodes the same image. The instance is resident, so an unbounded map would
// grow forever — each value is a full-resolution clipboard image — and the temp
// files would pile up. Cap the count and drop the evicted entry's temp file;
// re-display of an evicted entry simply re-decodes.
const TEX_CACHE_MAX = 40;
const texCache = new Map<string, Gdk.Texture>();

function cacheGet(id: string): Gdk.Texture | null {
  const tex = texCache.get(id);
  if (!tex) return null;
  texCache.delete(id); // re-insert to mark most-recently-used
  texCache.set(id, tex);
  return tex;
}

function cachePut(id: string, tex: Gdk.Texture): void {
  texCache.set(id, tex);
  while (texCache.size > TEX_CACHE_MAX) {
    const oldest = texCache.keys().next().value as string;
    texCache.delete(oldest);
    try {
      GLib.unlink(`${THUMB_DIR}/${oldest}`);
    } catch {
      // ignore — temp file already gone
    }
  }
}

function Thumbnail({ entry }: { entry: ClipEntry }) {
  const cached = cacheGet(entry.id);
  const [tex, setTex] = createState<Gdk.Texture | null>(cached);

  if (!cached) {
    const path = `${THUMB_DIR}/${entry.id}`;
    decodeToFile(entry, path)
      .then(() => {
        const texture = Gdk.Texture.new_from_filename(path);
        cachePut(entry.id, texture);
        setTex(texture);
      })
      .catch((err) =>
        console.error("spotlight/clipboard: thumbnail decode failed", err),
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
  onActivate,
  onDelete,
  registerButton,
}: {
  entry: ClipEntry;
  onActivate: () => void;
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
        onClicked={onActivate}
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

export default function ClipboardMode({ register, close, getWin }: ModeProps) {
  let searchentry: Gtk.Entry;

  const [entries, setEntries] = createState(list());
  const [query, setQuery] = createState("");

  // Item (entry) buttons by id, so the arrows step item-to-item and skip the
  // per-row trash buttons.
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
    try {
      Gio.File.new_for_path(THUMB_DIR).trash(null);
    } catch {
      // ignore — not worth surfacing on shutdown
    }
  });

  // Copy an entry and close. Always close once the attempt settles: copy()
  // re-resolves a stale id and never wipes the clipboard, so even an evicted
  // entry is a harmless no-op.
  function pick(entry: ClipEntry) {
    copy(entry)
      .then((ok) => {
        if (!ok)
          console.warn(
            "spotlight/clipboard: entry gone from history; not copied",
          );
      })
      .catch((err) => console.error("spotlight/clipboard: copy failed", err))
      .then(close);
  }

  function copyTop() {
    const top = shown()[0];
    if (top) pick(top);
  }

  function onDelete(entry: ClipEntry) {
    remove(entry).catch((err) =>
      console.error("spotlight/clipboard: delete failed", err),
    );
    setEntries(entries().filter((e) => e !== entry));
  }

  function searchHasFocus() {
    const focus = getWin()?.get_focus() ?? null;
    return (
      focus !== null &&
      (focus === searchentry || focus.is_ancestor(searchentry))
    );
  }

  function orderedItems(): Gtk.Button[] {
    return shown()
      .map((e) => itemButtons.get(e.id))
      .filter((b): b is Gtk.Button => b != null);
  }

  // Move focus prev/next between items (delta -1/+1), skipping trash buttons.
  function focusItem(delta: number) {
    const items = orderedItems();
    if (items.length === 0) return;
    if (searchHasFocus()) {
      if (delta > 0) items[0].grab_focus();
      return;
    }
    const focus = getWin()?.get_focus() ?? null;
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

  function onShow() {
    // Fresh state on every open: re-read the clipboard (it changes while we're
    // hidden), clear the previous search, and focus the entry.
    searchentry.set_text("");
    setQuery("");
    setEntries(list());
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      searchentry.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Up/Down walk between the search entry and the rows; Enter/Space activate the
  // focused row. Any other key while focus is in the list snaps back to search.
  // Escape is left to the shell's default close.
  function onKey(
    keyval: number,
    _mod: number,
    controller: Gtk.EventControllerKey,
  ) {
    if (keyval === Gdk.KEY_Escape) return false;
    if (keyval === Gdk.KEY_Down) {
      focusItem(1);
      return true;
    }
    if (keyval === Gdk.KEY_Up) {
      focusItem(-1);
      return true;
    }
    if (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter) {
      const focus = getWin()?.get_focus() ?? null;
      const onRow =
        focus !== null &&
        orderedItems().some(
          (b) => b === focus || b.get_parent() === focus.get_parent(),
        );
      if (onRow) return false;
      copyTop();
      return true;
    }

    const passthrough =
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

  register({ onShow, focus: () => searchentry.grab_focus(), onKey });

  return (
    <box
      class="mode mode-clipboard"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
      heightRequest={PANEL_CONTENT_H}
    >
      <entry
        $={(ref) => (searchentry = ref)}
        primaryIconName="system-search-symbolic"
        placeholderText="Search clipboard…"
        onNotifyText={({ text }) => setQuery(text)}
        onActivate={copyTop}
      />
      <Gtk.Separator />
      <Gtk.ScrolledWindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
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
                onActivate={() => pick(entry)}
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
  );
}
