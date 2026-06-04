import { Gtk, Gdk } from "ags/gtk4";
import GLib from "gi://GLib";
import Sidebar from "./Sidebar";
import WeekView, {
  HINT_ALPHA,
  endHints,
  feedHintKey,
  scrollGrid,
  startHints,
} from "./WeekView";
import EventDetails from "./EventDetails";
import CommandPalette from "./CommandPalette";
import InviteDialog from "./InviteDialog";
import ShortcutsDialog from "./ShortcutsDialog";
import RecurDialog from "./RecurDialog";
import RecurScopeDialog from "./RecurScopeDialog";
import FloatingEditor from "./FloatingEditor";
import AccountsModal from "./AccountsModal";
import QuitDialog from "./QuitDialog";
import LoadingOverlay from "./LoadingOverlay";
import NotificationArea from "./NotificationArea";
import { googleConfigured } from "./gmap";
import { createEvent, syncNow } from "./store";
import { startNotifier } from "./notifier";
import { initZoom, zoomIn, zoomOut, zoomReset } from "./zoom";
import {
  accountsOpen,
  anchor,
  closeSelected,
  defaultCal,
  goToday,
  hintMode,
  inviteDialog,
  paletteOpen,
  quitConfirmOpen,
  recurScopeOpen,
  resolveRecurScope,
  selected,
  setAccountsOpen,
  setInviteDialog,
  setLeftVisible,
  setPaletteIntent,
  setPaletteOpen,
  setQuitConfirmOpen,
  setRightVisible,
  setSelected,
  setShortcutsOpen,
  setView,
  shortcutsOpen,
  stepAnchor,
} from "./state";

import { HOUR_HEIGHT, NOW_HOUR } from "./datetime";

// Live (zoom changes HOUR_HEIGHT), so j/k scroll two hour-rows at any zoom.
const scrollStep = () => HOUR_HEIGHT * 2;

// Create a 1-hour event at the current time on the anchored day and open it.
function createNow() {
  const d = anchor.get();
  const start = Math.round(NOW_HOUR * 4) / 4;
  const ev = createEvent({
    title: "New event",
    start,
    end: Math.min(start + 1, 24),
    date: d,
    calendar: defaultCal.get(),
  });
  setSelected({ ev, date: d, isNew: true });
}

// Three-pane Notion Calendar layout in a regular window, with the command
// palette layered on top via an overlay. Escape closes whatever's open, else
// raises the quit-confirm. The window's close button instead hides to the tray.
export default function Calendar() {
  function onKey(
    e: Gtk.EventControllerKey,
    keyval: number,
    _code: number,
    state: number,
  ) {
    if (keyval === Gdk.KEY_k && (state & Gdk.ModifierType.CONTROL_MASK) !== 0) {
      setPaletteIntent("command");
      setPaletteOpen(true);
      return true;
    }

    // Ctrl +/- zoom, Ctrl+0 reset (works even while typing — it's app-wide).
    if ((state & Gdk.ModifierType.CONTROL_MASK) !== 0) {
      if (
        keyval === Gdk.KEY_plus ||
        keyval === Gdk.KEY_equal ||
        keyval === Gdk.KEY_KP_Add
      ) {
        zoomIn();
        return true;
      }
      if (keyval === Gdk.KEY_minus || keyval === Gdk.KEY_KP_Subtract) {
        zoomOut();
        return true;
      }
      if (keyval === Gdk.KEY_0 || keyval === Gdk.KEY_KP_0) {
        zoomReset();
        return true;
      }
    }

    // Hint mode (after "f"): type the hint chars to pick an event, Esc cancels.
    if (hintMode.get()) {
      if (keyval === Gdk.KEY_Escape) endHints();
      else {
        const ch = String.fromCharCode(Gdk.keyval_to_unicode(keyval));
        if (HINT_ALPHA.includes(ch)) feedHintKey(ch);
      }
      return true;
    }

    if (keyval === Gdk.KEY_Escape) {
      if (quitConfirmOpen.get()) setQuitConfirmOpen(false);
      else if (recurScopeOpen.get()) resolveRecurScope(null);
      else if (accountsOpen.get()) setAccountsOpen(false);
      else if (inviteDialog.get()) setInviteDialog(false);
      else if (shortcutsOpen.get()) setShortcutsOpen(false);
      else if (paletteOpen.get()) setPaletteOpen(false);
      else if (closeSelected()) {
        /* closed the editor (or raised the discard-invite dialog) */
      } else setQuitConfirmOpen(true); // nothing to dismiss → confirm quit
      return true;
    }

    // Single-key shortcuts: skip while a modal is up or while typing in a field.
    if (
      paletteOpen.get() ||
      inviteDialog.get() ||
      shortcutsOpen.get() ||
      accountsOpen.get() ||
      recurScopeOpen.get() ||
      quitConfirmOpen.get()
    )
      return false;
    if (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK))
      return false;
    const focus = (e.get_widget() as Gtk.Window)?.get_focus();
    if (focus instanceof Gtk.Text || focus instanceof Gtk.TextView)
      return false;

    switch (keyval) {
      case Gdk.KEY_t:
      case Gdk.KEY_T:
        goToday();
        return true;
      case Gdk.KEY_d:
      case Gdk.KEY_D:
        setView("day");
        return true;
      case Gdk.KEY_w:
      case Gdk.KEY_W:
        setView("week");
        return true;
      case Gdk.KEY_m:
      case Gdk.KEY_M:
        setView("month");
        return true;
      case Gdk.KEY_c: // c — create an event now
      case Gdk.KEY_C:
        createNow();
        return true;
      case Gdk.KEY_f: // f — show event hints
      case Gdk.KEY_F:
        startHints();
        return true;
      case Gdk.KEY_Left: // ← / h — previous period
      case Gdk.KEY_h:
      case Gdk.KEY_H:
        stepAnchor(-1);
        return true;
      case Gdk.KEY_Right: // → / l — next period
      case Gdk.KEY_l:
      case Gdk.KEY_L:
        stepAnchor(1);
        return true;
      case Gdk.KEY_j: // j / k — scroll the time grid
      case Gdk.KEY_J:
        scrollGrid(scrollStep());
        return true;
      case Gdk.KEY_k:
      case Gdk.KEY_K:
        scrollGrid(-scrollStep());
        return true;
      case Gdk.KEY_grave: // ` — toggle the left sidebar
        setLeftVisible((v) => !v);
        return true;
      case Gdk.KEY_asciitilde: // ~ — toggle the right details pane
        setRightVisible((v) => !v);
        return true;
      case Gdk.KEY_period: // . — open the palette on "Go to date…"
        setPaletteIntent("date");
        setPaletteOpen(true);
        return true;
      case Gdk.KEY_p: // P — open the palette on "Meet with…"
      case Gdk.KEY_P:
        setPaletteIntent("meet");
        setPaletteOpen(true);
        return true;
      case Gdk.KEY_question: // ? — show all keyboard shortcuts
        setShortcutsOpen(true);
        return true;
    }
    return false;
  }

  return (
    <Gtk.Window
      title="Calendar"
      defaultWidth={1680}
      defaultHeight={960}
      $={(w: Gtk.Window) => {
        // Hide to the tray instead of quitting; returning true keeps the window
        // alive (just unmapped) so the process — and tray — stay up. Quit from
        // the tray menu or the Escape quit-confirm. Wired here (not via
        // onCloseRequest) so the true return reliably suppresses the destroy.
        w.connect("close-request", () => (w.set_visible(false), true));
        initZoom(); // apply the persisted zoom now that GTK is up
        startNotifier(); // desktop reminders for upcoming events
        // Don't auto-focus the search entry on launch.
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
          w.set_focus(null);
          return GLib.SOURCE_REMOVE;
        });
        // Refresh when the window regains focus (catches edits made elsewhere).
        w.connect("notify::is-active", () => {
          if (w.isActive && googleConfigured()) void syncNow();
        });
      }}
    >
      <Gtk.EventControllerKey onKeyPressed={onKey} />
      <overlay>
        <box class="app">
          <Sidebar />
          <WeekView />
          <EventDetails />
        </box>
        <LoadingOverlay $type="overlay" />
        <FloatingEditor $type="overlay" />
        <CommandPalette $type="overlay" />
        <InviteDialog $type="overlay" />
        <ShortcutsDialog $type="overlay" />
        <RecurDialog $type="overlay" />
        <RecurScopeDialog $type="overlay" />
        <AccountsModal $type="overlay" />
        <QuitDialog $type="overlay" />
        <NotificationArea $type="overlay" />
      </overlay>
    </Gtk.Window>
  );
}
