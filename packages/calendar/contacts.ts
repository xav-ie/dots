// Contact resolution via Google's People API: turn a bare attendee email into a
// display name, avatar, source-account tag and timezone. Results accumulate in
// the maps below and `contactRev` is bumped so already-rendered participant rows
// re-read them. Shared by Participants.tsx (the saved/draft rows) and InviteDialog.
import { createState } from "ags";
import GLib from "gi://GLib";
import { fetch } from "ags/fetch";
import { PEOPLE, accountColor, type Suggestion } from "./data";
import { accountEmails, accountName } from "./auth";
import { accounts } from "./state";
import {
  getCalendarTimezone,
  searchContacts,
  searchDirectory,
  type GContact,
} from "./rest";

// Accumulates display names / cached photo paths for emails seen via the People
// API so ParticipantRow and InviteDialog can show a name + avatar instead of a
// bare address.
export const contactNames = new Map<string, string>();
export const contactPhotos = new Map<string, string>(); // email → local file path
export const contactSource = new Map<string, string>(); // email → account it came from
export const contactTz = new Map<string, string>(); // email → IANA timezone
// Bumped whenever a contact's name/photo lands, so already-rendered participant
// rows re-read the maps and show the resolved name + avatar.
export const [contactRev, setContactRev] = createState(0);
// Emails we've already looked up (success or not) so we don't re-query them.
const contactLookedUp = new Set<string>();

export const nameOf = (email: string) =>
  contactNames.get(email) ||
  PEOPLE.find((p) => p.subtitle === email)?.title ||
  email;

const CONTACT_PHOTO_DIR = `${GLib.get_user_cache_dir()}/calendar/contacts`;

// Download a contact's profile photo to a local cache path (keyed by email
// hash). Returns the path, or null if there's no URL or the fetch fails.
async function cacheContactPhoto(
  email: string,
  url: string,
): Promise<string | null> {
  const name =
    GLib.compute_checksum_for_string(GLib.ChecksumType.SHA256, email, -1) ??
    encodeURIComponent(email);
  const dest = `${CONTACT_PHOTO_DIR}/${name}`;
  try {
    const res = await fetch(url);
    if (res.status < 200 || res.status >= 300) return null;
    const buf = await res.arrayBuffer();
    GLib.mkdir_with_parents(CONTACT_PHOTO_DIR, 0o700);
    GLib.file_set_contents(dest, new Uint8Array(buf as ArrayBuffer));
    return dest;
  } catch {
    return null;
  }
}

// Populate contactNames/contactPhotos/contactSource from a contacts search
// result found via `account`. Returns true if anything new was cached.
async function ingestContacts(
  results: GContact[],
  account: string,
): Promise<boolean> {
  let changed = false;
  for (const c of results) {
    if (c.name && contactNames.get(c.email) !== c.name) {
      contactNames.set(c.email, c.name);
      changed = true;
    }
    if (!contactSource.has(c.email)) {
      contactSource.set(c.email, account);
      changed = true;
    }
    if (c.photo && !contactPhotos.has(c.email)) {
      const path = await cacheContactPhoto(c.email, c.photo);
      if (path) {
        contactPhotos.set(c.email, path);
        changed = true;
      }
    }
  }
  return changed;
}

// The People searchContacts API needs a "warmup" request (an empty query) to
// prime its per-account cache; the first real search otherwise returns empty.
// Fire one per account when the participants field appears.
const warmedUp = new Set<string>();
export function warmupContacts(): void {
  for (const account of accountEmails()) {
    if (warmedUp.has(account)) continue;
    warmedUp.add(account);
    searchContacts(account, "").catch(() => warmedUp.delete(account));
  }
}

// Search a query across every connected account's contacts in parallel, then
// merge: dedup by email (first account that has them wins), tag each with its
// source account's color dot.
export async function fetchContacts(query: string): Promise<Suggestion[]> {
  const emails = accountEmails();
  if (!emails.length) return [];
  // Per account: personal contacts + Workspace directory (colleagues not saved
  // as contacts). Directory only returns for Workspace accounts; errors (e.g. a
  // personal account, or missing scope) are swallowed.
  const perAccount = await Promise.all(
    emails.map((account) =>
      Promise.all([
        searchContacts(account, query).catch((err) => {
          console.error("contact search failed:", account, err);
          return [] as GContact[];
        }),
        searchDirectory(account, query).catch(() => [] as GContact[]),
      ]).then(([contacts, directory]) => {
        // Personal contacts first, then directory-only people.
        const byEmail = new Map<string, GContact>();
        for (const c of [...contacts, ...directory])
          if (!byEmail.has(c.email)) byEmail.set(c.email, c);
        return { account, results: [...byEmail.values()] };
      }),
    ),
  );
  let changed = false;
  const seen = new Set<string>();
  const out: Suggestion[] = [];
  for (const { account, results } of perAccount) {
    if (await ingestContacts(results, account)) changed = true;
    for (const c of results) {
      if (seen.has(c.email)) continue;
      seen.add(c.email);
      out.push({
        title: c.name,
        subtitle: c.email,
        source: account,
        dotColor: accountColor(account),
      });
    }
  }
  if (changed) setContactRev((n) => n + 1);
  return out;
}

// Resolve name + photo for already-saved participant emails (which never went
// through the add-field search). Looks each unknown email up across all
// connected accounts' contacts, caches what it finds, bumps contactRev.
export async function loadContactInfo(emails: string[]): Promise<void> {
  const accountList = accountEmails();
  if (!accountList.length) return;
  let changed = false;
  // A participant who is also a connected account has a real profile photo
  // already cached by the sync — prefer it (contacts often only hold the
  // generic silhouette, which the People API marks default and we skip).
  const connected = accounts.get();
  for (const email of emails) {
    const acct = connected.find((a) => a.account === email);
    if (acct?.photo && contactPhotos.get(email) !== acct.photo) {
      contactPhotos.set(email, acct.photo);
      changed = true;
    }
    // A connected account's own display name (from its Google profile).
    const ownName = accountName(email);
    if (ownName && contactNames.get(email) !== ownName) {
      contactNames.set(email, ownName);
      changed = true;
    }
  }
  for (const email of emails) {
    if (contactLookedUp.has(email)) continue;
    contactLookedUp.add(email);
    for (const account of accountList) {
      if (contactNames.has(email) && contactPhotos.has(email)) break;
      try {
        const [contacts, directory] = await Promise.all([
          searchContacts(account, email),
          searchDirectory(account, email).catch(() => [] as GContact[]),
        ]);
        const match = [...contacts, ...directory].find(
          (c) => c.email === email,
        );
        if (!match) continue;
        // Don't let a contact's default silhouette overwrite an account photo.
        if (contactPhotos.has(email)) delete (match as GContact).photo;
        if (await ingestContacts([match], account)) changed = true;
      } catch (err) {
        console.error("contact lookup failed:", email, account, err);
      }
    }
  }
  if (changed) setContactRev((n) => n + 1);
}

// Emails whose timezone we've already tried (success or not), so we don't requery.
const tzLookedUp = new Set<string>();

// Resolve each attendee's calendar timezone (their primary calendar == their
// email) so the editor can show the event's start in their local time. Only
// Workspace colleagues typically expose this; others 403 and are left unknown.
export async function loadContactTz(emails: string[]): Promise<void> {
  const accountList = accountEmails();
  if (!accountList.length) return;
  let changed = false;
  for (const email of emails) {
    if (tzLookedUp.has(email)) continue;
    tzLookedUp.add(email);
    for (const account of accountList) {
      const tz = await getCalendarTimezone(account, email);
      if (tz) {
        if (contactTz.get(email) !== tz) {
          contactTz.set(email, tz);
          changed = true;
        }
        break;
      }
    }
  }
  if (changed) setContactRev((n) => n + 1);
}
