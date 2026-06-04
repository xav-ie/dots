import { For, createComputed, createState } from "ags";
import { Gdk, Gtk } from "ags/gtk4";
import GLib from "gi://GLib";
import { PEOPLE, type CalAccount } from "./data";
import { ACCENT_ROWS, COLOR_ROWS } from "./palette";
import {
  MINI_DOW,
  NOW_HOUR,
  addMonths,
  fmtMonthYear,
  monthGrid,
  sameDay,
  startOfWeek,
  type MiniCell,
} from "./datetime";
import {
  accounts,
  anchor,
  defaultCal,
  draftHolder,
  hiddenCals,
  leftVisible,
  setAccountsOpen,
  setAnchor,
  setDefaultCal,
  setDraftInvites,
  setLeftVisible,
  setPaletteOpen,
  setSelected,
  setShortcutsOpen,
  sidebarToggle,
  toggleCal,
  view,
} from "./state";
import { createEvent, setCalendarColor } from "./store";
import { accent, setAccent } from "./theme";
import SuggestField, { emailFreeform } from "./SuggestField";
import { fetchContacts, nameOf } from "./contacts";
import { googleConfigured } from "./gmap";
import { iconPx, zoom, zoomIn, zoomOut, zoomReset } from "./zoom";
import { a11y } from "./a11y";

const START = Gtk.Align.START;

// Flat focus order for the account/calendar tree (account headers and their
// calendar rows, in DFS order). Up/Down step through it, skipping rows hidden by
// a collapsed account — so Down on a header enters its calendars, Down past the
// last calendar moves to the next account, etc.
const navItems: Gtk.Widget[] = [];
function navMove(current: Gtk.Widget, dir: number) {
  const i = navItems.indexOf(current);
  if (i < 0) return;
  for (let j = i + dir; j >= 0 && j < navItems.length; j += dir)
    if (navItems[j].get_mapped()) {
      navItems[j].grab_focus();
      return;
    }
}
function navKeys(w: Gtk.Widget, onActivate?: () => void) {
  navItems.push(w);
  const k = new Gtk.EventControllerKey();
  k.connect("key-pressed", (_c, kv: number) => {
    if (kv === Gdk.KEY_Down) return (navMove(w, 1), true);
    if (kv === Gdk.KEY_Up) return (navMove(w, -1), true);
    if (
      onActivate &&
      (kv === Gdk.KEY_Return || kv === Gdk.KEY_KP_Enter || kv === Gdk.KEY_space)
    )
      return (onActivate(), true);
    return false;
  });
  w.add_controller(k);
}

// Create a new event at the current time on the anchored day and open it.
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

// Create a meeting at the current time and open it with `email` as a *draft*
// invite (pending), so the user still confirms via "Send invite".
function meetWith(email: string) {
  const d = anchor.get();
  const start = Math.round(NOW_HOUR * 4) / 4;
  const ev = createEvent({
    title: `Meeting with ${nameOf(email)}`,
    start,
    end: Math.min(start + 1, 24),
    date: d,
    calendar: defaultCal.get(),
  });
  setSelected({ ev, date: d, isNew: true });
  // After the editor builds (which resets the draft), seed the pending invite.
  draftHolder.event = ev;
  setDraftInvites([email]);
}

// "Meet with…" field reusing the shared people-search popover.
function MeetWith() {
  return (
    <box class="meet-with">
      <SuggestField
        placeholder="Meet with…"
        icon="contact-new-symbolic"
        onSelect={meetWith}
        position={Gtk.PositionType.RIGHT}
        items={googleConfigured() ? [] : PEOPLE}
        fetchItems={googleConfigured() ? fetchContacts : undefined}
        freeform={emailFreeform}
      />
    </box>
  );
}

type MiniDay = MiniCell & {
  focus?: boolean;
  period?: boolean;
  pStart?: boolean;
  pEnd?: boolean;
};

function MiniDayCell(d: MiniDay) {
  const cls = ["mini-day"];
  if (d.dim) cls.push("dim");
  if (d.today) cls.push("today");
  if (d.period) cls.push("period");
  if (d.period && d.pStart) cls.push("p-start");
  if (d.period && d.pEnd) cls.push("p-end");
  return (
    // Only the focus target (today, else the selected day) is in the Tab chain,
    // so tabbing into the mini-calendar lands on it and one more Tab leaves —
    // it doesn't step through all 42 day cells. Mouse clicks still work on all.
    <button
      class={cls.join(" ")}
      canFocus={d.focus ?? false}
      onClicked={() => setAnchor(d.date)}
    >
      <label label={`${d.n}`} />
    </button>
  );
}

function MiniMonth() {
  const weeks = createComputed((): MiniDay[][] => {
    const grid = monthGrid(anchor());
    const a = anchor();
    const v = view();
    const hasToday = grid.some((w) => w.some((c) => c.today));
    const aWeek = startOfWeek(a);
    // Days inside the current view's period: just the anchored day (Day),
    // its week (Week), or the whole month (Month). This makes the red band
    // scale to what left/right navigation moves by. Compare by date (startOfWeek
    // keeps the time-of-day, so getTime() wouldn't match across midnight cells).
    const inPeriod = (c: MiniCell) =>
      v === "day"
        ? c.sel
        : v === "week"
          ? sameDay(startOfWeek(c.date), aWeek)
          : !c.dim;
    return grid.map((w) => {
      const flags = w.map(inPeriod);
      const first = flags.indexOf(true);
      const last = flags.lastIndexOf(true);
      return w.map((c, i) => ({
        ...c,
        focus: hasToday ? c.today : c.sel,
        period: flags[i],
        pStart: i === first,
        pEnd: i === last,
      }));
    });
  });
  return (
    <box class="mini-month" orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <box class="mini-head">
        <label
          class="mini-title"
          label={anchor((a) => fmtMonthYear(a))}
          hexpand
          halign={START}
        />
        <button
          class="icon-btn"
          tooltipText="Previous month"
          onClicked={() => setAnchor((a) => addMonths(a, -1))}
          $={(b: Gtk.Button) => a11y(b, "Previous month")}
        >
          <image iconName="pan-start-symbolic" pixelSize={iconPx(12)} />
        </button>
        <button
          class="icon-btn"
          tooltipText="Next month"
          onClicked={() => setAnchor((a) => addMonths(a, 1))}
          $={(b: Gtk.Button) => a11y(b, "Next month")}
        >
          <image iconName="pan-end-symbolic" pixelSize={iconPx(12)} />
        </button>
      </box>
      <box class="mini-row" homogeneous>
        {MINI_DOW.map((d) => (
          <label class="mini-dow" label={d} />
        ))}
      </box>
      <For each={weeks}>
        {(week: MiniDay[]) => (
          <box class="mini-row" homogeneous>
            {week.map((d) => MiniDayCell(d))}
          </box>
        )}
      </For>
    </box>
  );
}

function CalRow(cal: CalAccount["calendars"][number], account: string) {
  const isHidden = hiddenCals((s) => s.has(cal.name));
  const isDefault = defaultCal((d) => d === cal.name);
  let mb: Gtk.MenuButton;
  return (
    // A box (not a button) so the inner star button can receive its own clicks;
    // the row's click toggles visibility via a gesture. Made focusable with a
    // key controller so it's reachable by Tab and toggled with Enter/Space.
    <box
      class="cal-row"
      focusable
      $={(b: Gtk.Box) => navKeys(b, () => toggleCal(cal.name))}
    >
      <Gtk.GestureClick onReleased={() => toggleCal(cal.name)} />
      <box spacing={9}>
        {/* The swatch is a color picker: click it to recolor the calendar. */}
        <menubutton
          class="swatch-pick"
          valign={Gtk.Align.CENTER}
          tooltipText="Calendar color"
          $={(m: Gtk.MenuButton) => {
            mb = m;
            a11y(m, `${cal.name} color`);
          }}
        >
          <box
            class={isHidden(
              (h) =>
                `swatch ev-${cal.color}${cal.rss ? " rss" : ""}${h ? " off" : ""}`,
            )}
          />
          <popover class="cal-pop">
            <box
              class="color-grid"
              orientation={Gtk.Orientation.VERTICAL}
              spacing={6}
            >
              {COLOR_ROWS.map((row) => (
                <box class="color-row" spacing={6}>
                  {row.map((col) => (
                    <button
                      class={`color-dot${cal.color === col ? " sel" : ""}`}
                      $={(b: Gtk.Button) => a11y(b, `${col} color`)}
                      onClicked={() => {
                        mb.popdown();
                        // Defer the recolor: it rebuilds the <For> account list
                        // (new array ref), which tears down this very popover and
                        // button. Mutating mid-click frees the widget under us and
                        // crashes GTK, so let the click dispatch finish first.
                        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                          setCalendarColor(account, cal.id, cal.name, col);
                          return GLib.SOURCE_REMOVE;
                        });
                      }}
                    >
                      <box class={`swatch ev-${col}`} />
                    </button>
                  ))}
                </box>
              ))}
            </box>
          </popover>
        </menubutton>
        <label
          class={isHidden((h) => `cal-name${h ? " muted" : ""}`)}
          label={cal.name}
          halign={START}
          hexpand
          ellipsize={3}
          maxWidthChars={22}
        />
        {/* RSS / subscribed-feed marker. */}
        {cal.rss ? (
          <image
            class="cal-rss"
            iconName="application-rss+xml-symbolic"
            pixelSize={iconPx(11)}
            valign={Gtk.Align.CENTER}
          />
        ) : (
          <box />
        )}
        {/* star: sets the default calendar; shown on hover/focus, or always if
            default. Tabbable, so Tab from the focused row reaches it. Only for
            calendars you can write to — a read-only calendar can't be a default. */}
        {cal.writable ? (
          <button
            class={isDefault((d) => `star-btn${d ? " is-default" : ""}`)}
            tooltipText="Set as default calendar"
            onClicked={() => setDefaultCal(cal.name)}
            $={(b: Gtk.Button) =>
              a11y(
                b,
                isDefault((d) =>
                  d
                    ? `${cal.name} is the default calendar`
                    : `Set ${cal.name} as default calendar`,
                ),
              )
            }
          >
            <image
              class="star"
              iconName={isDefault((d) =>
                d ? "starred-symbolic" : "non-starred-symbolic",
              )}
              pixelSize={iconPx(13)}
            />
          </button>
        ) : (
          <box />
        )}
        {/* eye toggle: a real (tabbable) button. Always shown while hidden;
            otherwise only on row hover/focus (CSS). */}
        <button
          class={isHidden((h) => `eye-btn${h ? " always" : ""}`)}
          tooltipText={isHidden((h) => (h ? "Show calendar" : "Hide calendar"))}
          onClicked={() => toggleCal(cal.name)}
          $={(b: Gtk.Button) =>
            a11y(
              b,
              isHidden((h) => (h ? `Show ${cal.name}` : `Hide ${cal.name}`)),
            )
          }
        >
          <image
            iconName={isHidden((h) =>
              h ? "view-conceal-symbolic" : "view-reveal-symbolic",
            )}
            pixelSize={iconPx(13)}
          />
        </button>
      </box>
    </box>
  );
}

// A calendar account: a clickable header (with a caret) that collapses/expands
// its calendars. Expanded by default.
function AccountSection(acct: CalAccount) {
  const [open, setOpen] = createState(true);
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1}>
      <button
        class="account-head"
        onClicked={() => setOpen((o) => !o)}
        $={(b: Gtk.Button) => navKeys(b)}
      >
        <box spacing={5}>
          <image
            class="account-caret"
            iconName={open((o) =>
              o ? "pan-down-symbolic" : "pan-end-symbolic",
            )}
            pixelSize={iconPx(11)}
          />
          <label class="account" label={acct.account} halign={START} hexpand />
        </box>
      </button>
      <box
        orientation={Gtk.Orientation.VERTICAL}
        spacing={1}
        visible={open((o) => o)}
      >
        {acct.calendars.map((c) => CalRow(c, acct.account))}
      </box>
    </box>
  );
}

// Accent-color picker for the sidebar footer. The dot shows the live accent and
// opens a palette popover (the coral default + the 24 calendar colors); picking
// re-tints the whole app via theme.ts and persists. Reuses the calendar
// color-picker's popover styling.
function AccentPicker() {
  let mb: Gtk.MenuButton;
  return (
    <menubutton
      class="swatch-pick accent-pick"
      valign={Gtk.Align.CENTER}
      tooltipText="Accent color"
      $={(m: Gtk.MenuButton) => {
        mb = m;
        a11y(m, "Accent color");
      }}
    >
      <box class="accent-cur" />
      <popover class="cal-pop">
        <box
          class="color-grid"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={6}
        >
          {ACCENT_ROWS.map((row) => (
            <box class="color-row" spacing={6}>
              {row.map((opt) => (
                <button
                  class={accent((a) =>
                    a.toLowerCase() === opt.hex.toLowerCase()
                      ? "color-dot sel"
                      : "color-dot",
                  )}
                  tooltipText={opt.label}
                  $={(b: Gtk.Button) => a11y(b, `${opt.label} accent`)}
                  onClicked={() => {
                    mb.popdown();
                    setAccent(opt.hex);
                  }}
                >
                  <box class={`swatch ${opt.cls}`} />
                </button>
              ))}
            </box>
          ))}
        </box>
      </popover>
    </menubutton>
  );
}

export default function Sidebar() {
  return (
    <box
      class="sidebar left"
      orientation={Gtk.Orientation.VERTICAL}
      hexpand={false}
      visible={leftVisible((v) => v)}
    >
      <box class="side-top" spacing={6}>
        <button
          class="icon-btn"
          tooltipText="Collapse sidebar"
          onClicked={() => {
            setLeftVisible(false);
            // This button just unmapped; hand focus to the topbar expand button
            // (now visible) so it stays on the toggle instead of falling through
            // to the timezone "+". Deferred so the target is mapped first.
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
              sidebarToggle.left.expand?.();
              return GLib.SOURCE_REMOVE;
            });
          }}
          $={(b: Gtk.Button) => {
            a11y(b, "Collapse sidebar");
            sidebarToggle.left.collapse = () => b.grab_focus();
          }}
        >
          <image iconName="sidebar-show-symbolic" pixelSize={iconPx(15)} />
        </button>
        <box hexpand />
        <button
          class="icon-btn"
          tooltipText="Command menu (Ctrl+K)"
          onClicked={() => setPaletteOpen(true)}
          $={(b: Gtk.Button) => a11y(b, "Command menu")}
        >
          <image iconName="system-search-symbolic" pixelSize={iconPx(15)} />
        </button>
        <button
          class="icon-btn"
          tooltipText="New event"
          onClicked={createNow}
          $={(b: Gtk.Button) => a11y(b, "New event")}
        >
          <image iconName="document-edit-symbolic" pixelSize={iconPx(15)} />
        </button>
      </box>

      <scrolledwindow vexpand hscrollbarPolicy={Gtk.PolicyType.NEVER}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
          <MiniMonth />

          <MeetWith />

          {/* For reappends its items to the end of *its parent*, so give it a
              dedicated box — otherwise the static add-row below would be pushed
              above the account list. */}
          <box orientation={Gtk.Orientation.VERTICAL} spacing={1}>
            <For each={accounts}>
              {(acct: CalAccount) => AccountSection(acct)}
            </For>
          </box>

          <button class="add-row" onClicked={() => setAccountsOpen(true)}>
            <box spacing={8}>
              <image iconName="list-add-symbolic" pixelSize={iconPx(14)} />
              <label label="Add calendar account" halign={START} />
            </box>
          </button>
        </box>
      </scrolledwindow>

      <box class="side-foot" spacing={8}>
        <button
          class="icon-btn"
          tooltipText="Keyboard shortcuts (?)"
          onClicked={() => setShortcutsOpen(true)}
          $={(b: Gtk.Button) => a11y(b, "Keyboard shortcuts")}
        >
          <image iconName="help-about-symbolic" pixelSize={iconPx(15)} />
        </button>
        <AccentPicker />
        <box hexpand />
        {/* Zoom controls (Ctrl +/- / Ctrl+0). The percentage resets to 100%. */}
        <box class="zoom-ctl">
          <button
            class="icon-btn"
            tooltipText="Zoom out (Ctrl−)"
            onClicked={() => zoomOut()}
            $={(b: Gtk.Button) => a11y(b, "Zoom out")}
          >
            <image iconName="zoom-out-symbolic" pixelSize={iconPx(15)} />
          </button>
          <button
            class="zoom-level"
            tooltipText="Reset zoom (Ctrl+0)"
            onClicked={() => zoomReset()}
            $={(b: Gtk.Button) => a11y(b, "Reset zoom to 100%")}
          >
            <label label={zoom((z) => `${Math.round(z * 100)}%`)} />
          </button>
          <button
            class="icon-btn"
            tooltipText="Zoom in (Ctrl+)"
            onClicked={() => zoomIn()}
            $={(b: Gtk.Button) => a11y(b, "Zoom in")}
          >
            <image iconName="zoom-in-symbolic" pixelSize={iconPx(15)} />
          </button>
        </box>
      </box>
    </box>
  );
}
