import GLib from "gi://GLib";
import Gio from "gi://Gio";

// A real system-tray icon for the calendar. GTK4 dropped GtkStatusIcon and
// AppIndicator is GTK3-only (can't load into this GTK4 process), so we speak the
// StatusNotifierItem (SNI) + com.canonical.dbusmenu D-Bus protocols directly.
// Any SNI host — your AstalTray bar — then renders the icon with zero bar
// changes. The bar shows each item as a menubutton over its dbusmenu, so the
// menu (Open / Quit) is the primary interaction.

const SNI_XML = `
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <method name="Activate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="SecondaryActivate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="ContextMenu">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <method name="Scroll">
      <arg name="delta" type="i" direction="in"/>
      <arg name="orientation" type="s" direction="in"/>
    </method>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg name="status" type="s"/></signal>
    <signal name="NewToolTip"/>
  </interface>
</node>`;

const MENU_XML = `
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg name="id" type="i" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg name="events" type="a(isvu)" direction="in"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <method name="AboutToShowGroup">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="updatesNeeded" type="ai" direction="out"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <signal name="ItemsPropertiesUpdated">
      <arg name="updatedProps" type="a(ia{sv})"/>
      <arg name="removedProps" type="a(ias)"/>
    </signal>
    <signal name="LayoutUpdated">
      <arg name="revision" type="u"/>
      <arg name="parent" type="i"/>
    </signal>
    <signal name="ItemActivationRequested">
      <arg name="id" type="i"/>
      <arg name="timestamp" type="u"/>
    </signal>
  </interface>
</node>`;

export interface TrayHandlers {
  onOpen: () => void; // show / raise the window
  onQuit: () => void; // begin the (confirmed) quit
  iconName?: string; // initial icon (defaults to the coral "dots-calendar")
}

export interface TrayHandle {
  // Swap the tray icon (a pre-generated per-accent variant) and tell the host.
  setIcon(name: string): void;
}

// Menu entries by dbusmenu id. Flat list under the root (id 0).
const OPEN_ID = 1;
const QUIT_ID = 2;
const ITEMS = [
  { id: OPEN_ID, label: "Open Calendar" },
  { id: QUIT_ID, label: "Quit" },
];

const itemProps = (label: string) => ({
  label: GLib.Variant.new_string(label),
  enabled: GLib.Variant.new_boolean(true),
  visible: GLib.Variant.new_boolean(true),
});

export function setupTray({
  onOpen,
  onQuit,
  iconName,
}: TrayHandlers): TrayHandle {
  const conn = Gio.bus_get_sync(Gio.BusType.SESSION, null);

  const dispatch = (id: number) => {
    if (id === OPEN_ID) onOpen();
    else if (id === QUIT_ID) onQuit();
  };

  // com.canonical.dbusmenu — a static two-item menu.
  const menu = {
    Version: 3,
    Status: "normal",
    TextDirection: "ltr",
    IconThemePath: [] as string[],
    GetLayout() {
      // out args are (revision u, layout (ia{sv}av)). A multi-out method must
      // return an ARRAY of the out values (gjs packs each into the reply tuple) —
      // a single combined "(u(ia{sv}av))" variant marshals wrong and the menu
      // never builds. The layout itself is (id, props, children[]); children are
      // variant-boxed (ia{sv}av) items.
      const layout = new GLib.Variant("(ia{sv}av)", [
        0,
        { "children-display": GLib.Variant.new_string("submenu") },
        ITEMS.map(
          (it) =>
            new GLib.Variant("(ia{sv}av)", [it.id, itemProps(it.label), []]),
        ),
      ]);
      return [1, layout];
    },
    GetGroupProperties(ids: number[]) {
      const want = ids.length ? ids : ITEMS.map((it) => it.id);
      const rows = ITEMS.filter((it) => want.includes(it.id)).map(
        (it) =>
          [it.id, itemProps(it.label)] as [
            number,
            ReturnType<typeof itemProps>,
          ],
      );
      // Single out arg → return the bare a(ia{sv}) value (gjs wraps it).
      return new GLib.Variant("a(ia{sv})", rows);
    },
    GetProperty(id: number, name: string) {
      const it = ITEMS.find((x) => x.id === id);
      return GLib.Variant.new_string(it && name === "label" ? it.label : "");
    },
    Event(id: number, eventId: string) {
      if (eventId === "clicked") dispatch(id);
    },
    EventGroup(events: [number, string, unknown, number][]) {
      for (const [id, eventId] of events)
        if (eventId === "clicked") dispatch(id);
      return [];
    },
    AboutToShow() {
      return false; // static menu — never needs a rebuild
    },
    AboutToShowGroup() {
      return [[], []];
    },
  };

  // org.kde.StatusNotifierItem — icon + pointer to the menu above.
  const item = {
    Category: "ApplicationStatus",
    Id: "calendar",
    Title: "Calendar",
    Status: "Active",
    IconName: iconName ?? "dots-calendar",
    IconThemePath: "",
    ItemIsMenu: true,
    Menu: "/MenuBar",
    ToolTip: new GLib.Variant("(sa(iiay)ss)", [
      "dots-calendar",
      [],
      "Calendar",
      "",
    ]),
    Activate() {
      onOpen();
    },
    SecondaryActivate() {
      onOpen();
    },
    ContextMenu() {},
    Scroll() {},
  };

  Gio.DBusExportedObject.wrapJSObject(MENU_XML, menu).export(conn, "/MenuBar");
  const sniObj = Gio.DBusExportedObject.wrapJSObject(SNI_XML, item);
  sniObj.export(conn, "/StatusNotifierItem");

  // Own a unique well-known name (the SNI spec's service-name form) and register
  // it with the watcher. The unique-connection digits guarantee uniqueness.
  const num = (conn.get_unique_name() ?? ":1.0").replace(/[^0-9]/g, "") || "1";
  const busName = `org.kde.StatusNotifierItem-${num}-1`;

  const register = () =>
    conn.call(
      "org.kde.StatusNotifierWatcher",
      "/StatusNotifierWatcher",
      "org.kde.StatusNotifierWatcher",
      "RegisterStatusNotifierItem",
      new GLib.Variant("(s)", [busName]),
      null,
      Gio.DBusCallFlags.NONE,
      -1,
      null,
      (c, res) => {
        // Watcher may not be up yet; the name-watch below re-registers when it
        // appears, so a failure here is expected and silent.
        try {
          c?.call_finish(res);
        } catch {
          /* retried when the watcher (bar) shows up */
        }
      },
    );

  Gio.bus_own_name_on_connection(
    conn,
    busName,
    Gio.BusNameOwnerFlags.NONE,
    () => register(),
    null,
  );
  // Re-register whenever the watcher (re)appears — the bar may start after us or
  // restart on a config reload.
  Gio.bus_watch_name_on_connection(
    conn,
    "org.kde.StatusNotifierWatcher",
    Gio.BusNameWatcherFlags.NONE,
    () => register(),
    null,
  );

  return {
    setIcon(name: string) {
      if (name === item.IconName) return;
      item.IconName = name;
      // NewIcon (no args) tells the SNI host to re-read IconName; the empty
      // tuple is the signal's (absent) parameter list.
      try {
        sniObj.emit_signal("NewIcon", new GLib.Variant("()", []));
      } catch (e) {
        console.error(`[calendar-tray] NewIcon emit failed: ${e}`);
      }
    },
  };
}
