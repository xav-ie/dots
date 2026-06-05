import { Accessor, createEffect, createState, For, onCleanup } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import AstalApps from "gi://AstalApps";
import GLib from "gi://GLib";
import { frecencyStore } from "../../lib/frecency";
import { Store } from "../../lib/frecency";
import { createSelection, scrollIntoView } from "../../lib/selection";
import { ModeProps, PANEL_CONTENT_H } from "./types";

const MAX_RESULTS = 8;

function AppRow({
  application,
  cls,
  onActivate,
  registerButton,
}: {
  application: AstalApps.Application;
  cls: Accessor<string>;
  onActivate: () => void;
  registerButton: (button: Gtk.Button | null) => void;
}) {
  onCleanup(() => registerButton(null));
  const desc = application.description;
  return (
    <button
      class={cls}
      $={(ref) => registerButton(ref as Gtk.Button)}
      onClicked={onActivate}
    >
      <box spacing={12}>
        <image
          iconName={application.iconName || "application-x-executable"}
          pixelSize={54}
        />
        <box
          orientation={Gtk.Orientation.VERTICAL}
          valign={Gtk.Align.CENTER}
          hexpand
          halign={Gtk.Align.START}
        >
          <label
            class="app-name"
            label={application.name}
            halign={Gtk.Align.START}
            maxWidthChars={48}
            ellipsize={3 /* PANGO_ELLIPSIZE_END */}
          />
          {desc ? (
            <label
              class="app-desc"
              label={desc}
              halign={Gtk.Align.START}
              maxWidthChars={56}
              ellipsize={3}
            />
          ) : null}
        </box>
      </box>
    </button>
  );
}

export default function AppMode({ register, close }: ModeProps) {
  let searchentry: Gtk.Entry;
  let scroller: Gtk.ScrolledWindow;
  let listBox: Gtk.Box;

  const apps = new AstalApps.Apps();
  const fr = frecencyStore("app");
  // Snapshots refreshed on each show (the instance is resident): the frecency
  // store and the app list can both change between opens.
  let frecency: Store = fr.load();
  let allApps: AstalApps.Application[] = apps.fuzzy_query("");

  // Row button per app entry, so the selection can scroll the highlighted row
  // into view without walking focus.
  const itemButtons = new Map<string, Gtk.Button>();

  // Empty query → most frecent first. Typed query → AstalApps' fuzzy relevance
  // first, with frecency breaking ties between comparably-matching apps.
  function rank(text: string): AstalApps.Application[] {
    const q = text.trim();
    if (q === "") {
      return [...allApps]
        .sort(
          (a, b) => fr.score(frecency, b.entry) - fr.score(frecency, a.entry),
        )
        .slice(0, MAX_RESULTS);
    }
    return apps
      .fuzzy_query(q)
      .map((a) => ({ a, s: apps.fuzzy_score(q, a) }))
      .sort((x, y) =>
        y.s !== x.s
          ? y.s - x.s
          : fr.score(frecency, y.a.entry) - fr.score(frecency, x.a.entry),
      )
      .slice(0, MAX_RESULTS)
      .map((x) => x.a);
  }

  const [results, setResults] = createState<AstalApps.Application[]>(rank(""));
  const sel = createSelection(results);

  function search(text: string) {
    setResults(rank(text));
  }

  function launch(application?: AstalApps.Application) {
    if (!application) return;
    fr.bump(application.entry);
    application.launch();
    close();
  }

  // Keep the highlighted row visible as the arrows move it (or as a new query
  // resets it to the top).
  createEffect(() => {
    const item = sel.current();
    if (!item) return;
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      scrollIntoView(scroller, listBox, itemButtons.get(item.entry));
      return GLib.SOURCE_REMOVE;
    });
  });

  function onShow() {
    frecency = fr.load();
    allApps = apps.fuzzy_query("");
    searchentry.set_text("");
    setResults(rank(""));
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      searchentry.grab_focus();
      return GLib.SOURCE_REMOVE;
    });
  }

  // Focus stays on the entry; the arrows just slide the highlight. Enter is the
  // entry's default action (onActivate → launch the highlighted app). Escape is
  // left to the shell's default close.
  function onKey(keyval: number) {
    if (keyval === Gdk.KEY_Down) {
      sel.move(1);
      return true;
    }
    if (keyval === Gdk.KEY_Up) {
      sel.move(-1);
      return true;
    }
    return false;
  }

  register({ onShow, focus: () => searchentry.grab_focus(), onKey });

  return (
    <box
      class="mode mode-app"
      orientation={Gtk.Orientation.VERTICAL}
      spacing={12}
      heightRequest={PANEL_CONTENT_H}
    >
      <entry
        $={(ref) => (searchentry = ref)}
        primaryIconName="system-search-symbolic"
        placeholderText="Search apps…"
        onNotifyText={({ text }) => search(text)}
        onActivate={() => launch(sel.current())}
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
          spacing={2}
        >
          <label
            class="dim"
            label="No matches."
            visible={results((r) => r.length === 0)}
          />
          <For each={results}>
            {(application) => (
              <AppRow
                application={application}
                cls={sel.cls(application, "row")}
                onActivate={() => launch(application)}
                registerButton={(btn) => {
                  if (btn) itemButtons.set(application.entry, btn);
                  else itemButtons.delete(application.entry);
                }}
              />
            )}
          </For>
        </box>
      </Gtk.ScrolledWindow>
    </box>
  );
}
