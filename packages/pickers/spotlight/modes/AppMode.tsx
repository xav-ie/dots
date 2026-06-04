import { createState, For, onCleanup } from "ags";
import { Gtk, Gdk } from "ags/gtk4";
import AstalApps from "gi://AstalApps";
import GLib from "gi://GLib";
import { frecencyStore } from "../../lib/frecency";
import { Store } from "../../lib/frecency";
import { ModeProps, PANEL_CONTENT_H } from "./types";

const MAX_RESULTS = 8;

function AppRow({
  application,
  onActivate,
  registerButton,
}: {
  application: AstalApps.Application;
  onActivate: () => void;
  registerButton: (button: Gtk.Button | null) => void;
}) {
  onCleanup(() => registerButton(null));
  const desc = application.description;
  return (
    <button
      class="row"
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

export default function AppMode({ register, close, getWin }: ModeProps) {
  let searchentry: Gtk.Entry;

  const apps = new AstalApps.Apps();
  const fr = frecencyStore("app");
  // Snapshots refreshed on each show (the instance is resident): the frecency
  // store and the app list can both change between opens.
  let frecency: Store = fr.load();
  let allApps: AstalApps.Application[] = apps.fuzzy_query("");

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

  function search(text: string) {
    setResults(rank(text));
  }

  function launch(application?: AstalApps.Application) {
    if (!application) return;
    fr.bump(application.entry);
    application.launch();
    close();
  }

  function launchTop() {
    launch(results.get()[0]);
  }

  function searchHasFocus() {
    const focus = getWin()?.get_focus() ?? null;
    return (
      focus !== null &&
      (focus === searchentry || focus.is_ancestor(searchentry))
    );
  }

  function orderedItems(): Gtk.Button[] {
    return results
      .get()
      .map((a) => itemButtons.get(a.entry))
      .filter((b): b is Gtk.Button => b != null);
  }

  function focusItem(delta: number) {
    const items = orderedItems();
    if (items.length === 0) return;
    if (searchHasFocus()) {
      if (delta > 0) items[0].grab_focus();
      return;
    }
    const focus = getWin()?.get_focus() ?? null;
    const cur = items.findIndex((b) => b === focus);
    if (cur === -1) {
      if (delta > 0) items[0].grab_focus();
      return;
    }
    const next = cur + delta;
    if (next < 0) searchentry.grab_focus();
    else if (next < items.length) items[next].grab_focus();
  }

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
      const onRow = focus !== null && orderedItems().some((b) => b === focus);
      if (onRow) return false;
      launchTop();
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
        onActivate={launchTop}
      />
      <Gtk.Separator />
      <Gtk.ScrolledWindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <label
            class="dim"
            label="No matches."
            visible={results((r) => r.length === 0)}
          />
          <For each={results}>
            {(application) => (
              <AppRow
                application={application}
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
