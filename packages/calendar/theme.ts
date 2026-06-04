// Runtime accent color. The stylesheet references the GTK named color @accent
// (default defined in style.scss); here we redefine it live via a dedicated CSS
// provider added above the base stylesheet's priority, so a user pick re-tints
// every accent-derived shade (alpha()/mix() track the override). Persisted to
// the settings table; the picker lives in the sidebar footer (Sidebar.tsx).
import { createState } from "ags";
import { Gdk, Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import * as db from "./db";
import { ACCENT_DEFAULT_HEX, accentIcon } from "./palette";

function loadAccent(): string {
  const v = db.getSetting("accent");
  return /^#[0-9a-fA-F]{6}$/.test(v) ? v : ACCENT_DEFAULT_HEX;
}

// Current accent hex. Reactive so the footer picker's selection + the live dot
// reflect changes; CSS itself updates through the provider below, not this.
export const [accent, setAccentRaw] = createState(loadAccent());

let provider: Gtk.CssProvider | null = null;

// Install (once) the override provider on the default display and push the
// current accent into it. Safe to call before/after the window exists.
export function applyAccent(): void {
  const display = Gdk.Display.get_default();
  if (!display) return;
  if (!provider) {
    provider = new Gtk.CssProvider();
    // One above the base stylesheet (added at PRIORITY_USER) so our @accent
    // definition wins the cascade.
    Gtk.StyleContext.add_provider_for_display(
      display,
      provider,
      Gtk.STYLE_PROVIDER_PRIORITY_USER + 1,
    );
  }
  provider.load_from_string(`@define-color accent ${accent.get()};`);
}

export function setAccent(hex: string): void {
  if (hex === accent.get()) return;
  setAccentRaw(hex);
  db.setSetting("accent", hex);
  applyAccent();
  syncDesktopIcon();
}

// The installed (read-only) calendar.desktop, from the first XDG system data dir
// that has it — the source we clone for the user override below.
function systemDesktopEntry(): string | null {
  for (const dir of GLib.get_system_data_dirs()) {
    const path = `${dir}/applications/calendar.desktop`;
    if (!GLib.file_test(path, GLib.FileTest.EXISTS)) continue;
    const [ok, bytes] = GLib.file_get_contents(path);
    if (ok) return new TextDecoder().decode(bytes);
  }
  return null;
}

// Mirror the accent onto the launcher/taskbar icon. Unlike the tray, the desktop
// Icon= is read by *external* programs from the read-only store entry, so we
// can't repaint it directly — instead we drop a user override at
// ~/.local/share/applications/calendar.desktop (shadows the store one by
// desktop-id) whose Icon= points at the accent's pre-generated variant. AstalApps
// launchers monitor that dir and reload. Best-effort: a no-op when the system
// entry isn't on XDG_DATA_DIRS (e.g. `nix run`), and the default accent removes
// the override so the built-in coral entry applies again.
export function syncDesktopIcon(): void {
  const dir = `${GLib.get_user_data_dir()}/applications`;
  const override = `${dir}/calendar.desktop`;
  const icon = accentIcon(accent.get());
  if (icon === "dots-calendar") {
    try {
      Gio.File.new_for_path(override).delete(null);
    } catch {
      /* no override to remove */
    }
    return;
  }
  try {
    const base = systemDesktopEntry();
    if (!base) return;
    GLib.mkdir_with_parents(dir, 0o755);
    GLib.file_set_contents(
      override,
      base.replace(/^Icon=.*$/m, `Icon=${icon}`),
    );
  } catch (e) {
    console.error(`[calendar] desktop icon sync failed: ${e}`);
  }
}
