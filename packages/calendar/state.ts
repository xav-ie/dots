// Shared reactive UI state. Module-level singletons so any component can read
// and mutate them. `anchor` is the focused date that drives the week/day grid,
// the month title, and the mini-calendar selection.
import { createState } from "ags";
import {
  DEFAULT_TZS,
  TODAY,
  addDays,
  addMonths,
  startOfWeek,
  today,
  type Tz,
} from "./datetime";
import { ACCOUNTS, type CalAccount, type CalEvent } from "./data";
import type { Recur } from "./recur";
import * as db from "./db";
import { accountEmails } from "./auth";
import { queryFreeBusy, type BusyInterval } from "./rest";

db.init(); // idempotent; ensures the settings/events tables exist before reads

export type View = "week" | "day" | "month";

// The sidebar's account/calendar tree. Reactive so a Google sync (or a newly
// connected account) re-renders it. Seeded from the cache, falling back to the
// dummy ACCOUNTS when nothing is connected yet (UI demo).
const cachedAccounts = db.getCachedAccounts();
export const [accounts, setAccounts] = createState(
  (cachedAccounts.length ? cachedAccounts : ACCOUNTS) as CalAccount[],
);

// Whether the accounts/login modal is open.
export const [accountsOpen, setAccountsOpen] = createState(false);

// A clicked event plus the date of the column it was clicked on.
export interface Selection {
  ev: CalEvent;
  date: Date;
  // Newly-created event: the editor should open with the title in edit mode.
  isNew?: boolean;
}
export const [selected, setSelected] = createState(null as Selection | null);
// Bounds (in window coords) of the chip an event was opened from, so the
// floating editor can position itself next to it. Null → no anchor (e.g. a
// keyboard/command-created event) → the editor floats at the top-right.
export interface FloatAnchor {
  x: number;
  y: number;
  w: number;
  h: number;
  rw: number;
  rh: number;
}
export const [floatAnchor, setFloatAnchor] = createState(
  null as FloatAnchor | null,
);
export const [search, setSearch] = createState("");
// Id of an event to briefly flash in the grid (e.g. after picking a search hit).
export const [flashId, setFlashId] = createState(null as string | null);
// Vimium-style event-hint mode (press "f" to label visible events).
export const [hintMode, setHintMode] = createState(false);
export const [paletteOpen, setPaletteOpen] = createState(false);
// Which mode the palette should open into (set by a shortcut before opening).
export type PaletteIntent = "command" | "date" | "meet";
export const [paletteIntent, setPaletteIntent] = createState(
  "command" as PaletteIntent,
);

// Draft invite flow: unsent participant emails, the event they belong to, and
// whether the "send / discard?" dialog is showing.
export const [draftInvites, setDraftInvites] = createState([] as string[]);
export const [inviteDialog, setInviteDialog] = createState(false);
export const [shortcutsOpen, setShortcutsOpen] = createState(false);
// Confirm dialog shown when Escape would otherwise quit the app.
export const [quitConfirmOpen, setQuitConfirmOpen] = createState(false);

// Close the open event editor. With pending unsent invitees, raise the
// "send / discard?" dialog instead of closing outright (so Escape and the X
// button behave identically — and an untouched draft event still gets discarded
// via the selection-change handler in store.ts). Returns true if it acted.
export function closeSelected(): boolean {
  if (!selected.get()) return false;
  if (draftInvites.get().length) setInviteDialog(true);
  else setSelected(null);
  return true;
}

// Custom recurrence ("Repeat") dialog: open flag + the event context it edits.
export const [recurDialog, setRecurDialog] = createState(false);
export const recurHolder = {
  date: TODAY as Date,
  initial: null as Recur | null,
  apply: (_r: Recur | null) => {},
};
export const draftHolder = { event: null as CalEvent | null };

// Recurring-event edit scope: which occurrences an edit/delete/move applies to.
export type RecurScope = "this" | "following" | "all";
// Open flag + context for the scope chooser. `verb` tailors the wording (and the
// move variant shows what happens to the old vs new calendar). `allow` hides
// options that don't apply (e.g. changing the repeat rule has no "this"). `apply`
// resolves the askRecurScope() promise — null on cancel.
export const [recurScopeOpen, setRecurScopeOpen] = createState(false);
export const recurScopeHolder = {
  verb: "edit" as "edit" | "delete" | "move",
  title: "",
  dest: "", // destination calendar name, for the move variant
  allow: { this: true, following: true, all: true },
  apply: (_scope: RecurScope | null) => {},
};
export function askRecurScope(opts: {
  verb: "edit" | "delete" | "move";
  title: string;
  dest?: string;
  allow?: Partial<{ this: boolean; following: boolean; all: boolean }>;
}): Promise<RecurScope | null> {
  return new Promise((resolve) => {
    // A second ask while one is pending would orphan the first resolver (its
    // caller would never revert/push). Abandon the pending one cleanly first.
    if (recurScopeOpen.get()) recurScopeHolder.apply(null);
    recurScopeHolder.verb = opts.verb;
    recurScopeHolder.title = opts.title;
    recurScopeHolder.dest = opts.dest ?? "";
    recurScopeHolder.allow = {
      this: true,
      following: true,
      all: true,
      ...opts.allow,
    };
    recurScopeHolder.apply = resolve;
    setRecurScopeOpen(true);
  });
}
export function resolveRecurScope(scope: RecurScope | null) {
  recurScopeHolder.apply(scope);
  recurScopeHolder.apply = () => {};
  setRecurScopeOpen(false);
}
// Invitees whose busy preview is toggled off (their diamond shows as an outline).
export const [invitePreviewOff, setInvitePreviewOff] = createState(
  new Set<string>(),
);
export function toggleInvitePreview(email: string) {
  setInvitePreviewOff((s) => {
    const n = new Set(s);
    if (n.has(email)) n.delete(email);
    else n.add(email);
    return n;
  });
}
export const clearDraft = () => {
  setDraftInvites([]);
  setInvitePreviewOff(new Set());
  setSavedPreview(new Set());
  draftHolder.event = null;
};

// Already-saved participants whose busy preview the user toggled ON (drafts
// preview by default; saved attendees are off until their diamond is clicked).
export const [savedPreview, setSavedPreview] = createState(new Set<string>());
export function toggleSavedPreview(email: string) {
  setSavedPreview((s) => {
    const n = new Set(s);
    if (n.has(email)) n.delete(email);
    else n.add(email);
    return n;
  });
}

// Freebusy cache: email → busy intervals for the visible week window.
// Populated by refreshFreeBusy(); empty map = no data yet / not signed in.
export const [freeBusy, setFreeBusy] = createState(
  new Map<string, BusyInterval[]>(),
);

// True while a freebusy fetch is in flight. Used to show a loading spinner on
// the diamond buttons instead of stale/empty data.
export const [freeBusyLoading, setFreeBusyLoading] = createState(false);

// Fetch freebusy for the current draft invitees over the visible week. Called
// whenever draftInvites, anchor, or accounts change. No-ops when no account is
// connected. A generation counter discards responses from superseded requests
// (rapid week navigation or invitee changes can race).
let freeBusyGen = 0;

export async function refreshFreeBusy(anchorDate: Date): Promise<void> {
  // Draft invitees (previewed by default) plus saved attendees the user toggled
  // on. Deduped so an email in both isn't queried twice.
  const emails = [...new Set([...draftInvites.get(), ...savedPreview.get()])];
  const accountList = accountEmails();
  if (!emails.length || !accountList.length) {
    setFreeBusy(new Map());
    setFreeBusyLoading(false);
    return;
  }
  const gen = ++freeBusyGen;
  const from = startOfWeek(anchorDate);
  const to = addDays(from, 7);
  setFreeBusyLoading(true);
  try {
    // An attendee's calendar may only be visible to one of the connected
    // accounts (e.g. a Workspace colleague is visible to the Workspace account,
    // not a personal one). Query each account for the attendees still
    // unresolved and merge — queryFreeBusy omits attendees it can't access.
    const merged = new Map<string, BusyInterval[]>();
    for (const account of accountList) {
      const pending = emails.filter((e) => !merged.has(e));
      if (!pending.length) break;
      try {
        const res = await queryFreeBusy(account, pending, from, to);
        for (const [email, intervals] of res) merged.set(email, intervals);
      } catch (err) {
        console.error("freebusy fetch failed:", account, err);
      }
    }
    if (gen === freeBusyGen) {
      setFreeBusyLoading(false);
      setFreeBusy(merged);
    }
  } catch (err) {
    console.error("freebusy fetch failed:", err);
    if (gen === freeBusyGen) setFreeBusyLoading(false);
  }
}

export const [leftVisible, setLeftVisible] = createState(true);
export const [rightVisible, setRightVisible] = createState(true);

// The sidebar-toggle buttons register their focus grabs here. Each side has a
// collapse button in its pane and an expand button in the topbar, sitting in the
// same spot but in different containers — so clicking one unmaps it (its
// container's `visible` flips) and GTK would otherwise scatter focus to the next
// tabbable widget (the timezone "+"). Each click handler instead moves focus to
// its counterpart, which just appeared, keeping focus on the toggle. The ` / ~
// keyboard toggles deliberately leave these untouched, so focus stays put.
// Right side only does this when no event is selected — otherwise the floating
// editor (on collapse) / details pane (on expand) focuses the event title.
export const sidebarToggle = {
  left: {
    collapse: null as (() => void) | null,
    expand: null as (() => void) | null,
  },
  right: {
    collapse: null as (() => void) | null,
    expand: null as (() => void) | null,
  },
};
export const [view, setView] = createState("week" as View);
export const [anchor, setAnchor] = createState(TODAY);
export const [allDayExpanded, setAllDayExpanded] = createState(true);

// Calendars toggled off in the sidebar; their events drop out of the grid.
export const [hiddenCals, setHiddenCals] = createState(new Set<string>());

// The calendar new events default to (exactly one). Starred in the sidebar,
// persisted to the settings table.
export const [defaultCal, setDefaultCalRaw] = createState(
  db.getSetting("defaultCal") || "you@example.com",
);
export function setDefaultCal(name: string) {
  setDefaultCalRaw(name);
  db.setSetting("defaultCal", name);
}
// Navigation helpers shared by the command palette, keybindings, and topbar.
export const goToday = () => setAnchor(today());
// Step the anchor by one period in the active view (day / week / month).
export function stepAnchor(dir: number) {
  const v = view.get();
  setAnchor((a) =>
    v === "month" ? addMonths(a, dir) : addDays(a, dir * (v === "day" ? 1 : 7)),
  );
}
// Gutter timezones (index 0 is the default/primary). Persisted as JSON.
function loadTzs(): Tz[] {
  const raw = db.getSetting("timezones");
  if (raw) {
    try {
      const a = JSON.parse(raw);
      if (Array.isArray(a) && a.length) return a;
    } catch {
      // fall through to defaults
    }
  }
  return DEFAULT_TZS;
}
export const [timezones, setTimezonesRaw] = createState(loadTzs());
function persistTzs(t: Tz[]) {
  db.setSetting("timezones", JSON.stringify(t));
}
export function addTimezone(tz: Tz) {
  setTimezonesRaw((cur) => {
    if (cur.some((t) => t.label === tz.label && t.utc === tz.utc)) return cur;
    const next = [...cur, tz];
    persistTzs(next);
    return next;
  });
}
export function removeTimezone(i: number) {
  setTimezonesRaw((cur) => {
    if (i <= 0 || i >= cur.length) return cur; // never remove the default
    const next = cur.filter((_, j) => j !== i);
    persistTzs(next);
    return next;
  });
}
export function makeDefaultTimezone(i: number) {
  setTimezonesRaw((cur) => {
    if (i <= 0 || i >= cur.length) return cur;
    const next = [cur[i], ...cur.filter((_, j) => j !== i)];
    persistTzs(next);
    return next;
  });
}

export function toggleCal(name: string) {
  setHiddenCals((s) => {
    const n = new Set(s);
    if (n.has(name)) n.delete(name);
    else n.add(name);
    return n;
  });
}
