import { For, createComputed, createState, onCleanup } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";
import { clearChildren } from "./gtkutil";
import GLib from "gi://GLib";
import { PEOPLE, accountColor, type CalEvent } from "./data";
import { personColor } from "./palette";
import { systemIANA } from "./datetime";
import {
  draftHolder,
  draftInvites,
  freeBusy,
  freeBusyLoading,
  invitePreviewOff,
  savedPreview,
  setDraftInvites,
  setInvitePreviewOff,
  setSavedPreview,
  toggleInvitePreview,
  toggleSavedPreview,
} from "./state";
import {
  attendeeStatusOf,
  commitInvites,
  refreshAttendees,
  rev,
  setAttendeeOptional,
  syncNow,
  updateEvent,
} from "./store";
import {
  contactPhotos,
  contactRev,
  contactSource,
  contactTz,
  fetchContacts,
  loadContactInfo,
  loadContactTz,
  nameOf,
  warmupContacts,
} from "./contacts";
import SuggestField, { emailFreeform } from "./SuggestField";
import { googleConfigured } from "./gmap";
import { a11y } from "./a11y";

const START = Gtk.Align.START;

// The event's start rendered in `tz` (the attendee's zone), or null when the
// zone is unknown or matches the event's own zone (no point showing it twice).
function localStart(ev: CalEvent | undefined, tz: string | undefined): string {
  if (!ev || !tz || !ev.date || ev.start == null) return "";
  const ref = ev.timezone || systemIANA();
  if (tz === ref) return "";
  const hh = Math.floor(ev.start);
  const mm = Math.round((ev.start - hh) * 60);
  const instant = new Date(ev.date[0], ev.date[1], ev.date[2], hh, mm);
  try {
    return new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hour: "numeric",
      minute: "2-digit",
    }).format(instant);
  } catch {
    return "";
  }
}

// True if the event overlaps any of `email`'s busy intervals. Handles all-day
// and multi-day spans: an all-day (or each fully-covered middle day of a span)
// conflicts with any busy block that day; the first/last day of a timed span
// only conflicts within the event's own start/end hours.
function conflicts(ev: CalEvent | undefined, email: string): boolean {
  if (!ev || !ev.date) return false;
  const busy = freeBusy.get().get(email) ?? [];
  if (!busy.length) return false;
  const pad = (n: number) => String(n).padStart(2, "0");
  const dayStr = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const allDayLike = ev.allDay || ev.start == null || ev.end == null;
  const start = new Date(ev.date[0], ev.date[1], ev.date[2]);
  const end = ev.endDate
    ? new Date(ev.endDate[0], ev.endDate[1], ev.endDate[2])
    : start;
  const startStr = dayStr(start);
  const endStr = dayStr(end);
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    const slots = busy.filter((b) => b.date === dayStr(d));
    if (!slots.length) continue;
    if (allDayLike) return true; // any busy on a covered all-day = conflict
    const ds = dayStr(d);
    const lo = ds === startStr ? ev.start! : 0;
    const hi = ds === endStr ? ev.end! : 24;
    if (slots.some((b) => b.start < hi && b.end > lo)) return true;
  }
  return false;
}

// Green check / red x shown after the name once an attendee has responded.
function rsvpMark(status: CalEvent["status"]): Gtk.Widget | null {
  if (status === "accepted")
    return (
      <label class="rsvp-mark accepted" label="✓" valign={Gtk.Align.CENTER} />
    ) as Gtk.Widget;
  if (status === "declined")
    return (
      <label class="rsvp-mark declined" label="✗" valign={Gtk.Align.CENTER} />
    ) as Gtk.Widget;
  return null;
}

export function ParticipantRow(
  email: string,
  opts: {
    pending?: boolean;
    status?: CalEvent["status"];
    ev?: CalEvent; // the event being edited, for local-time + conflict display
    onRemove?: () => void;
  } = {},
): Gtk.Widget {
  let pop: Gtk.Popover;
  // RSVP mark, repainted when a sync (rev) lands a fresh attendee response so an
  // open editor shows a guest's acceptance without being reopened.
  const markSlot = (<box valign={Gtk.Align.CENTER} />) as Gtk.Box;
  const paintMark = () => {
    clearChildren(markSlot);
    const m = rsvpMark(attendeeStatusOf(opts.ev?.id, email) ?? opts.status);
    if (m) markSlot.append(m);
  };
  paintMark();
  onCleanup(rev.subscribe(paintMark));
  const [opt, setOpt] = createState(!!opts.ev?.optional?.[email]);
  const hasPhoto = () => contactPhotos.has(email);
  // Whether this row's busy is currently requested (so the spinner only shows
  // for people actually being fetched).
  const wantsPreview = () =>
    opts.pending
      ? !invitePreviewOff.get().has(email)
      : savedPreview.get().has(email);
  return (
    <box class="participant" spacing={8}>
      <image
        class="participant-avatar"
        file={contactRev(() => contactPhotos.get(email) ?? "")}
        pixelSize={iconPx(28)}
        valign={Gtk.Align.CENTER}
        visible={contactRev(() => hasPhoto())}
      />
      <image
        iconName="avatar-default-symbolic"
        pixelSize={iconPx(28)}
        valign={Gtk.Align.CENTER}
        visible={contactRev(() => !hasPhoto())}
      />
      <box orientation={Gtk.Orientation.VERTICAL} hexpand halign={START}>
        <box spacing={6} halign={START}>
          <label
            class={opt((o) => `participant-name${o ? " optional" : ""}`)}
            label={contactRev(() => nameOf(email))}
            halign={START}
            ellipsize={3}
          />
          <box
            class={contactRev(() => {
              const src = contactSource.get(email);
              return src
                ? `sg-account-dot ev-${accountColor(src)}`
                : "sg-account-dot hidden";
            })}
            tooltipText={contactRev(() => contactSource.get(email) ?? "")}
            valign={Gtk.Align.CENTER}
          />
          {markSlot}
          {/* red ! when the event overlaps this attendee's busy time. Reads rev
              + freeBusy so it tracks both a drag-move and freebusy loading. */}
          <label
            class="conflict-mark"
            label="!"
            tooltipText="Conflicts with their schedule"
            valign={Gtk.Align.CENTER}
            visible={createComputed(() => {
              rev();
              freeBusy();
              return conflicts(opts.ev, email);
            })}
          />
        </box>
        <label
          class="participant-email muted"
          label={email}
          halign={START}
          ellipsize={3}
          visible={contactRev(() => nameOf(email) !== email)}
        />
        {/* the event's start in this attendee's timezone, when it differs.
            Reads rev + contactRev so it tracks a drag-move and tz loading. */}
        <label
          class="participant-localtime muted"
          label={createComputed(() => {
            rev();
            contactRev();
            const t = localStart(opts.ev, contactTz.get(email));
            return t ? `${t} their time` : "";
          })}
          halign={START}
          ellipsize={3}
          visible={createComputed(() => {
            rev();
            contactRev();
            return localStart(opts.ev, contactTz.get(email)) !== "";
          })}
        />
      </box>
      {/* three-dots menu (left of the diamond) */}
      <menubutton
        class="part-menu"
        tooltipText="Participant options"
        valign={Gtk.Align.CENTER}
        $={(m: Gtk.MenuButton) => a11y(m, `Options for ${email}`)}
      >
        <image iconName="view-more-symbolic" pixelSize={iconPx(14)} />
        <popover class="part-pop" $={(p: Gtk.Popover) => (pop = p)}>
          <box class="part-menu-box" orientation={Gtk.Orientation.VERTICAL}>
            <button
              class="part-item"
              onClicked={() => {
                pop.popdown();
                const next = !opt.get();
                setOpt(next);
                if (opts.ev) void setAttendeeOptional(opts.ev, email, next);
              }}
            >
              <label
                label={opt((o) => (o ? "Mark required" : "Mark optional"))}
                halign={START}
              />
            </button>
            <button
              class="part-item"
              onClicked={() => {
                pop.popdown();
                opts.onRemove?.();
              }}
            >
              <label label="Remove" halign={START} />
            </button>
          </box>
        </popover>
      </menubutton>
      {/* busy-preview diamond: only shown while drafting invites (a scheduling
          aid). Drafts default-on (toggle off via invitePreviewOff); saved
          attendees default-off (toggle on via savedPreview). The spinner
          overlays the button while that person's first freebusy fetch runs. */}
      <overlay
        class="diamond-stack"
        valign={Gtk.Align.CENTER}
        visible={draftInvites((d) => opts.pending || d.length > 0)}
      >
        <button
          class="diamond-btn"
          tooltipText="Toggle busy-time preview"
          onClicked={() =>
            opts.pending
              ? toggleInvitePreview(email)
              : toggleSavedPreview(email)
          }
          $={(b: Gtk.Button) =>
            a11y(b, `Toggle busy-time preview for ${email}`)
          }
        >
          <label
            class={`pending-diamond ev-${personColor(email)}`}
            label={
              opts.pending
                ? invitePreviewOff((s) => (s.has(email) ? "◇" : "◆"))
                : savedPreview((s) => (s.has(email) ? "◆" : "◇"))
            }
          />
        </button>
        <Gtk.Spinner
          $type="overlay"
          spinning={freeBusyLoading(
            (l) => l && wantsPreview() && !freeBusy.get().has(email),
          )}
          visible={freeBusyLoading(
            (l) => l && wantsPreview() && !freeBusy.get().has(email),
          )}
          widthRequest={iconPx(16)}
          heightRequest={iconPx(16)}
          halign={Gtk.Align.CENTER}
          valign={Gtk.Align.CENTER}
        />
      </overlay>
    </box>
  ) as Gtk.Widget;
}

// Yes / No / Maybe RSVP — sets the event status (persisted, restyles the chip).
function Rsvp(ev: CalEvent) {
  const btns: Record<string, Gtk.Button> = {};
  const paint = () => {
    const cur = ev.status ?? "accepted";
    for (const k in btns)
      if (cur === k) btns[k].add_css_class("sel");
      else btns[k].remove_css_class("sel");
  };
  const set = (s: CalEvent["status"]) => {
    if (s === (ev.status ?? "accepted")) return; // already the current RSVP
    updateEvent(ev.id, "status", s!, true); // sets ev.status (or reverts it async)
    paint();
  };
  const seg = (label: string, status: CalEvent["status"]) => (
    <button
      class="rsvp"
      $={(b: Gtk.Button) => (btns[status!] = b)}
      onClicked={() => set(status)}
    >
      <label label={label} />
    </button>
  );
  const row = (
    <box class="rsvp-row" halign={START}>
      {seg("Yes", "accepted")}
      {seg("No", "declined")}
      {seg("Maybe", "maybe")}
    </box>
  ) as Gtk.Widget;
  paint();
  // Repaint if the status reverts (a cancelled recurring-scope dialog bumps rev),
  // so the chip doesn't stay stuck on the optimistically-selected choice.
  onCleanup(rev.subscribe(paint));
  return row;
}

// Participants: add field, the saved list, plus a draft-invite flow — newly
// added people are "pending" (red diamond) until you click Send invite.
export function Participants(ev: CalEvent) {
  // Fresh draft per event card. Only notify when there's actually a draft to
  // clear — a bare reset would bump the draft signal on every selection, which
  // rebuilds the day columns (and, in the popover path, destroys the chip).
  if (draftInvites.get().length) setDraftInvites([]);
  if (invitePreviewOff.get().size) setInvitePreviewOff(new Set());
  if (savedPreview.get().size) setSavedPreview(new Set());
  draftHolder.event = ev;
  warmupContacts(); // prime the People API so the first search isn't empty
  // Pull the latest guest responses so checkmarks are current on open (the marks
  // repaint reactively when this lands), not stale until the next background sync.
  if (ev.participants) void refreshAttendees(ev);

  // Order: accepted first, declined next, then maybe / no-response last.
  const rsvpRank = (email: string): number => {
    switch (ev.attendeeStatus?.[email]) {
      case "accepted":
        return 0;
      case "declined":
        return 1;
      default:
        return 2;
    }
  };
  const initial = (
    ev.participants ? ev.participants.split(",").filter(Boolean) : []
  ).sort((a, b) => rsvpRank(a) - rsvpRank(b));
  const [saved, setSaved] = createState(initial);
  // Resolve names/photos + timezones for saved attendees not yet cached.
  if (initial.length) {
    void loadContactInfo(initial);
    void loadContactTz(initial);
  }

  const add = (email: string) => {
    if (!email) return;
    const d = draftInvites.get();
    if (d.includes(email) || saved.get().includes(email)) return;
    draftHolder.event = ev;
    void loadContactTz([email]);
    // Starting a draft → preview everyone's busy by default (existing attendees
    // included), so the grid shows all schedules at once for finding a slot.
    if (!d.length) setSavedPreview(new Set(saved.get()));
    setDraftInvites([...d, email]);
  };
  const send = () => {
    const d = draftInvites.get();
    if (!d.length) return;
    // Optimistically move the draft into the saved list; on a permanent write
    // failure commitInvites' callback rolls these back so the rows don't lie.
    commitInvites(ev, d, () =>
      setSaved(saved.get().filter((x) => !d.includes(x))),
    );
    setSaved([...saved.get(), ...d]);
    setDraftInvites([]);
    // Drafting is over → drop busy-preview state so no blocks linger in the grid.
    if (invitePreviewOff.get().size) setInvitePreviewOff(new Set());
    if (savedPreview.get().size) setSavedPreview(new Set());
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 3000, () => {
      void syncNow();
      return GLib.SOURCE_REMOVE;
    });
  };
  const removeSaved = (email: string) => {
    const next = saved.get().filter((x) => x !== email);
    setSaved(next);
    ev.participants = next.join(",");
    updateEvent(ev.id, "participants", ev.participants);
  };
  const removeDraft = (email: string) =>
    setDraftInvites(draftInvites.get().filter((x) => x !== email));

  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <SuggestField
        placeholder="Add participant or room"
        icon="contact-new-symbolic"
        position={Gtk.PositionType.LEFT}
        items={googleConfigured() ? [] : PEOPLE}
        fetchItems={googleConfigured() ? fetchContacts : undefined}
        freeform={emailFreeform}
        onSelect={add}
        clearOnSelect
      />
      <box
        class="participants"
        orientation={Gtk.Orientation.VERTICAL}
        spacing={1}
      >
        <For each={saved}>
          {(e: string) =>
            ParticipantRow(e, {
              status: ev.attendeeStatus?.[e],
              ev,
              onRemove: () => removeSaved(e),
            })
          }
        </For>
        <For each={draftInvites}>
          {(e: string) =>
            ParticipantRow(e, {
              pending: true,
              ev,
              onRemove: () => removeDraft(e),
            })
          }
        </For>
      </box>
      <button
        class="send-invite"
        visible={draftInvites((d) => d.length > 0)}
        onClicked={send}
      >
        <label label="Send invite" />
      </button>
      {Rsvp(ev)}
    </box>
  );
}
