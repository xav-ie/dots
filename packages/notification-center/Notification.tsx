import Gtk from "gi://Gtk?version=4.0";
import Gdk from "gi://Gdk?version=4.0";
import GLib from "gi://GLib";
import Pango from "gi://Pango";
import AstalNotifd from "gi://AstalNotifd";

// Adapted from the official Aylur/ags gtk4 notifications example, shared between
// the transient popups and the persistent center list.

function isIcon(icon?: string | null): boolean {
  const theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default()!);
  return !!icon && theme.has_icon(icon);
}

// Notification `image-path` may be a plain path or a file:// URI.
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

function fileExists(path?: string | null): boolean {
  const p = toPath(path);
  return !!p && GLib.file_test(p, GLib.FileTest.EXISTS);
}

// Render an arbitrary image file at a thumbnail size. Gtk.Image draws file images
// at icon size (tiny), so use Gdk.Texture + Gtk.Picture like the clipboard picker.
function NotifImage({ path }: { path: string }) {
  const p = toPath(path);
  let tex: Gdk.Texture | null = null;
  try {
    if (p) tex = Gdk.Texture.new_from_filename(p);
  } catch {
    tex = null;
  }
  if (!tex) return <box />;
  return (
    <box
      class="image"
      valign={Gtk.Align.START}
      widthRequest={64}
      heightRequest={64}
      overflow={Gtk.Overflow.HIDDEN}
    >
      <Gtk.Picture
        contentFit={Gtk.ContentFit.COVER}
        hexpand
        vexpand
        paintable={tex}
      />
    </box>
  );
}

// nm-applet sends its bundled raster names (nm-signal-75, nm-device-wired, …)
// via app-icon / image-path. Map them onto the Adwaita `network-*-symbolic` set
// the bar uses so popups match. Mirror of packages/bar/modules/Tray.tsx
// nmSymbolic — keep in sync.
function nmSymbolic(name?: string | null): string | null {
  if (!name || !name.startsWith("nm-")) return null;
  const signal = name.match(/^nm-signal-(\d+)/);
  if (signal) {
    const n = Number(signal[1]);
    if (n >= 88) return "network-wireless-signal-excellent-symbolic";
    if (n >= 63) return "network-wireless-signal-good-symbolic";
    if (n >= 38) return "network-wireless-signal-ok-symbolic";
    if (n >= 13) return "network-wireless-signal-weak-symbolic";
    return "network-wireless-signal-none-symbolic";
  }
  if (name.startsWith("nm-vpn-connecting"))
    return "network-vpn-acquiring-symbolic";
  if (name.startsWith("nm-vpn")) return "network-vpn-symbolic";
  if (name.startsWith("nm-stage")) return "network-wireless-acquiring-symbolic";
  if (name.startsWith("nm-device-wired")) return "network-wired-symbolic";
  if (name.startsWith("nm-device-wireless")) return "network-wireless-symbolic";
  if (
    name.startsWith("nm-tech-") ||
    name.startsWith("nm-mb-") ||
    name.startsWith("nm-wwan")
  )
    return "network-cellular-symbolic";
  if (name === "nm-adhoc") return "network-wireless-hotspot-symbolic";
  if (name === "nm-no-connection") return "network-offline-symbolic";
  return null;
}

// An icon name with nm-applet's raster names swapped for the symbolic set.
function nmIcon(name?: string | null): string | null {
  return nmSymbolic(name) ?? name ?? null;
}

// 12-hour clock with AM/PM, e.g. "9:41 PM".
function time(unix: number): string {
  const d = GLib.DateTime.new_from_unix_local(unix);
  let h = d.get_hour();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  return `${h}:${d.get_minute().toString().padStart(2, "0")} ${ampm}`;
}

function urgency(n: AstalNotifd.Notification): string {
  const { LOW, CRITICAL } = AstalNotifd.Urgency;
  if (n.urgency === LOW) return "low";
  if (n.urgency === CRITICAL) return "critical";
  return "normal";
}

// The list's first child is the always-present (usually hidden) "empty" label,
// and rows can sprout focusable action buttons — so step over anything that
// isn't itself focusable when walking row-to-row.
function nextFocusable(w?: Gtk.Widget | null): Gtk.Widget | null {
  let s = w?.get_next_sibling() ?? null;
  while (s && !s.get_focusable()) s = s.get_next_sibling();
  return s;
}
function prevFocusable(w?: Gtk.Widget | null): Gtk.Widget | null {
  let s = w?.get_prev_sibling() ?? null;
  while (s && !s.get_focusable()) s = s.get_prev_sibling();
  return s;
}

interface NotificationProps {
  notification: AstalNotifd.Notification;
  // Center rows are focusable, fire the default action on Enter/Backspace, and
  // show a close (X) button; toast popups are passive and omit all of that.
  selectable?: boolean;
}

export default function Notification({
  notification: n,
  selectable,
}: NotificationProps) {
  // Default action (freedesktop "default", else the first action), fired when a
  // selectable center row is activated with Enter.
  function activate() {
    const a = n.actions.find((x) => x.id === "default") ?? n.actions[0];
    if (a) n.invoke(a.id);
  }

  // Drop the freedesktop "default" action and any unlabelled action from the
  // button row: "default" is the click-the-body action (fired via activate or a
  // body click), not a button, and senders like Claude Code include it with an
  // empty label — rendering it produced a blank button.
  const buttons = n.actions.filter(
    (a) => a.id !== "default" && a.label.trim() !== "",
  );

  // A body click invokes the "default" action when the sender provides one
  // (e.g. Claude Code's "needs your permission" focuses the terminal); invoking
  // resolves the notification, so no separate dismiss is needed. With no default
  // action, a body click just dismisses.
  function bodyClick() {
    const def = n.actions.find((x) => x.id === "default");
    if (def) n.invoke(def.id);
    else n.dismiss();
  }

  return (
    <box
      class={`notification ${urgency(n)}`}
      orientation={Gtk.Orientation.VERTICAL}
      focusable={selectable}
    >
      {/* Click anywhere on the notification invokes its default action (else
          dismisses). Fire on release, not press: an action button claims the
          click sequence during the press, which denies this ancestor gesture so
          `released` never reaches it — the button keeps working. Acting on press
          would instead resolve the notification before the button's onClicked
          runs, leaving n.invoke() a no-op (the daemon only invokes RECEIVED
          notifications). */}
      <Gtk.GestureClick onReleased={bodyClick} />
      {selectable && (
        <Gtk.EventControllerKey
          onKeyPressed={(_c: Gtk.EventControllerKey, keyval: number) => {
            const row = _c.get_widget();
            if (keyval === Gdk.KEY_Return || keyval === Gdk.KEY_KP_Enter) {
              activate();
              return true;
            }
            // ↓/↑ jump row-to-row (skipping a row's action buttons); Tab is
            // left to GTK's default traversal so it steps through the action
            // buttons within a row before moving on.
            if (keyval === Gdk.KEY_Down) {
              const sib = nextFocusable(row);
              if (sib) {
                sib.grab_focus();
                return true;
              }
              return false;
            }
            if (keyval === Gdk.KEY_Up) {
              const sib = prevFocusable(row);
              if (sib) {
                sib.grab_focus();
                return true;
              }
              return false;
            }
            if (keyval === Gdk.KEY_BackSpace || keyval === Gdk.KEY_Delete) {
              // Remove the focused notification, then move focus to a neighbour
              // so you can keep deleting without re-selecting.
              const sib = nextFocusable(row) ?? prevFocusable(row);
              n.dismiss();
              if (sib)
                GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                  sib.grab_focus();
                  return GLib.SOURCE_REMOVE;
                });
              return true;
            }
            return false;
          }}
        />
      )}
      <box class="content">
        {n.image && fileExists(n.image) && <NotifImage path={n.image} />}
        {n.image && isIcon(nmIcon(n.image)) && (
          <box valign={Gtk.Align.START} class="icon-image">
            <image
              iconName={nmIcon(n.image)}
              pixelSize={48}
              halign={Gtk.Align.CENTER}
              valign={Gtk.Align.CENTER}
            />
          </box>
        )}
        <box orientation={Gtk.Orientation.VERTICAL} hexpand>
          <box class="title-row">
            <label
              class="summary"
              hexpand
              halign={Gtk.Align.FILL}
              xalign={0}
              maxWidthChars={1}
              ellipsize={Pango.EllipsizeMode.END}
              label={n.summary}
            />
            {selectable && (
              <label
                class="time"
                halign={Gtk.Align.END}
                valign={Gtk.Align.START}
                label={time(n.time)}
              />
            )}
          </box>
          {n.body && (
            <label
              class="body"
              wrap
              useMarkup
              maxWidthChars={1}
              halign={Gtk.Align.FILL}
              xalign={0}
              label={n.body}
            />
          )}
        </box>
      </box>
      {buttons.length > 0 && (
        <box class="actions" homogeneous>
          {buttons.map(({ label, id }) => (
            <button hexpand onClicked={() => n.invoke(id)}>
              <label label={label} halign={Gtk.Align.CENTER} hexpand />
            </button>
          ))}
        </box>
      )}
    </box>
  ) as Gtk.Widget;
}
