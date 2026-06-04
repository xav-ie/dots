// Google OAuth for the calendar app: a PKCE "installed app" flow with a loopback
// redirect, plus a per-account token store. This owns onboarding (the login
// modal calls addAccount) and hands out fresh access tokens to rest.ts.
//
// Client credentials (the reusable Google "Desktop app" client) live in a plain
// local file: ~/.config/calendar/client.json {client_id, client_secret}. The
// per-account refresh/access tokens land in ~/.local/share/calendar/accounts.json.
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Soup from "gi://Soup?version=3.0";
import { fetch } from "ags/fetch";

const CONFIG_DIR = `${GLib.get_user_config_dir()}/calendar`;
const DATA_DIR = `${GLib.get_user_data_dir()}/calendar`;
const CLIENT_FILE = `${CONFIG_DIR}/client.json`;
const ACCOUNTS_FILE = `${DATA_DIR}/accounts.json`;

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo";
// Full calendar + profile + contacts scopes. directory.readonly lets Workspace
// accounts search/resolve colleagues who aren't in personal contacts.
const SCOPE = [
  "https://www.googleapis.com/auth/calendar",
  "https://www.googleapis.com/auth/userinfo.profile",
  "https://www.googleapis.com/auth/contacts.readonly",
  "https://www.googleapis.com/auth/directory.readonly",
].join(" ");

interface Client {
  client_id: string;
  client_secret: string;
}

interface Account {
  email: string;
  refresh: string;
  access: string;
  expiry: number; // epoch seconds; refresh slightly before this
  photo?: string; // Google profile picture URL
  name?: string; // Google profile display name
}

// --- small JSON-file helpers -------------------------------------------------

function readJson<T>(path: string): T | null {
  try {
    const [ok, bytes] = GLib.file_get_contents(path);
    if (!ok) return null;
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
  } catch {
    return null;
  }
}

function writeJson(dir: string, path: string, obj: unknown) {
  GLib.mkdir_with_parents(dir, 0o700);
  GLib.file_set_contents(path, JSON.stringify(obj, null, 2));
}

// --- client + account stores -------------------------------------------------

export function loadClient(): Client | null {
  const c = readJson<Client>(CLIENT_FILE);
  return c?.client_id && c?.client_secret ? c : null;
}

export const hasClient = () => loadClient() !== null;
export const clientFilePath = () => CLIENT_FILE;

function loadAccountStore(): Account[] {
  return readJson<Account[]>(ACCOUNTS_FILE) ?? [];
}

function saveAccountStore(accounts: Account[]) {
  writeJson(DATA_DIR, ACCOUNTS_FILE, accounts);
}

// Connected account emails (for the sidebar / accounts modal).
export const accountEmails = (): string[] =>
  loadAccountStore().map((a) => a.email);

// Remote profile picture URL for an account, if we have one.
export const accountPhotoUrl = (email: string): string | null =>
  loadAccountStore().find((a) => a.email === email)?.photo ?? null;

// Stored profile display name for a connected account, if we have one.
export const accountName = (email: string): string | null =>
  loadAccountStore().find((a) => a.email === email)?.name ?? null;

export function removeAccount(email: string) {
  saveAccountStore(loadAccountStore().filter((a) => a.email !== email));
}

// --- PKCE helpers ------------------------------------------------------------

function base64url(bytes: Uint8Array): string {
  return GLib.base64_encode(bytes)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function randomVerifier(): string {
  const bytes = new Uint8Array(32);
  for (let i = 0; i < bytes.length; i++)
    bytes[i] = Math.floor(Math.random() * 256);
  return base64url(bytes);
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++)
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function challengeFor(verifier: string): string {
  const hex = GLib.compute_checksum_for_string(
    GLib.ChecksumType.SHA256,
    verifier,
    -1,
  );
  if (!hex) throw new Error("sha256 unavailable");
  return base64url(hexToBytes(hex));
}

// --- token endpoint ----------------------------------------------------------

const form = (params: Record<string, string>) =>
  Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
}

const now = () => Math.floor(Date.now() / 1000);

async function tokenRequest(
  params: Record<string, string>,
): Promise<TokenResponse> {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form(params),
  });
  const text = await res.text();
  if (res.status < 200 || res.status >= 300)
    throw new Error(`token endpoint ${res.status}: ${text}`);
  const data = JSON.parse(text);
  if (
    !data ||
    typeof data.access_token !== "string" ||
    typeof data.expires_in !== "number"
  )
    throw new Error(`unexpected token response: ${text.slice(0, 200)}`);
  return data as TokenResponse;
}

// In-flight refresh per account, so concurrent calls (multi-calendar sync) share
// one refresh instead of each doing its own read-modify-write of accounts.json.
const refreshing = new Map<string, Promise<string>>();

// Return a valid access token for `email`. `force` skips the cache (used on a
// 401, where the cached token is unexpired but server-side invalid).
export async function accessTokenFor(
  email: string,
  force = false,
): Promise<string> {
  if (!force) {
    const acct = loadAccountStore().find((a) => a.email === email);
    if (acct?.access && now() < acct.expiry) return acct.access;
  }
  let p = refreshing.get(email);
  if (!p) {
    p = refreshToken(email).finally(() => refreshing.delete(email));
    refreshing.set(email, p);
  }
  return p;
}

async function refreshToken(email: string): Promise<string> {
  const client = loadClient();
  if (!client) throw new Error("missing client.json");
  const refresh = loadAccountStore().find((a) => a.email === email)?.refresh;
  if (!refresh) throw new Error(`no such account: ${email}`);
  const tok = await tokenRequest({
    grant_type: "refresh_token",
    refresh_token: refresh,
    client_id: client.client_id,
    client_secret: client.client_secret,
  });
  // Backfill the display name / photo for accounts connected before we started
  // storing them (one extra userinfo call, only while a field is missing).
  const existing = loadAccountStore().find((a) => a.email === email);
  const info =
    existing && (!existing.name || !existing.photo)
      ? await fetchUserInfo(tok.access_token)
      : {};
  // Re-read just before saving (after the network round-trip), so a concurrent
  // refresh of a *different* account isn't clobbered by a stale snapshot.
  const accounts = loadAccountStore();
  const acct = accounts.find((a) => a.email === email);
  if (acct) {
    acct.access = tok.access_token;
    acct.expiry = now() + tok.expires_in - 60;
    if (!acct.name && info.name) acct.name = info.name;
    if (!acct.photo && info.picture) acct.photo = info.picture;
    saveAccountStore(accounts);
  }
  return tok.access_token;
}

// --- loopback consent flow ---------------------------------------------------

// Tiny calendar favicon (app accent), served on the success page.
const FAVICON_SVG =
  "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>" +
  "<rect width='16' height='16' rx='3' fill='#eb5757'/>" +
  "<rect x='3' y='4.5' width='10' height='8.5' rx='1.2' fill='#fff'/>" +
  "<rect x='3' y='4.5' width='10' height='2.6' fill='#eb5757'/>" +
  "<rect x='4.6' y='2.6' width='1.4' height='3' rx='.7' fill='#eb5757'/>" +
  "<rect x='10' y='2.6' width='1.4' height='3' rx='.7' fill='#eb5757'/></svg>";

// Wait for Google to redirect to our loopback server with ?code=… (or ?error=).
// Resolves with the authorization code. Returns the bound redirect URI too.
function awaitCode(): { redirect: string; code: Promise<string> } {
  const server = new Soup.Server();
  server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
  const uris = server.get_uris();
  const port = uris[0].get_port();
  const redirect = `http://127.0.0.1:${port}/`;

  const code = new Promise<string>((resolve, reject) => {
    let done = false; // one-shot: the browser also hits /favicon.ico, etc.
    const timeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 300, () => {
      server.disconnect();
      reject(new Error("timed out waiting for Google sign-in"));
      return GLib.SOURCE_REMOVE;
    });
    server.add_handler("/", (_srv, msg) => {
      msg.set_status(200, null);
      // The browser auto-requests /favicon.ico for the success page; serve a
      // little calendar icon so the tab isn't blank.
      if (msg.get_uri().get_path() === "/favicon.ico") {
        msg.set_response(
          "image/svg+xml",
          Soup.MemoryUse.COPY,
          new TextEncoder().encode(FAVICON_SVG),
        );
        return;
      }
      // Subsequent requests just get a blank page.
      if (done) {
        msg.set_response("text/html", Soup.MemoryUse.COPY, new Uint8Array(0));
        return;
      }
      done = true;
      const query = msg.get_uri().get_query() ?? "";
      const params = new Map(
        query.split("&").map((p) => {
          const [k, v] = p.split("=");
          return [k, decodeURIComponent(v ?? "")] as [string, string];
        }),
      );
      const err = params.get("error");
      const code = params.get("code");
      const ok = !err && code;
      const body =
        "<html><body style='font-family:sans-serif;padding:3em;text-align:center'>" +
        (ok
          ? "<h2>Calendar connected ✓</h2><p>You can close this tab and return to Calendar.</p>"
          : `<h2>Sign-in failed</h2><p>${err ?? "no authorization code"}</p>`) +
        "</body></html>";
      msg.set_response(
        "text/html; charset=utf-8",
        Soup.MemoryUse.COPY,
        new TextEncoder().encode(body),
      );
      GLib.source_remove(timeout);
      // Defer teardown: disconnecting synchronously here would close the socket
      // before libsoup writes the response, leaving the browser with a blank
      // page. Give it a moment to flush first.
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
        server.disconnect();
        return GLib.SOURCE_REMOVE;
      });
      if (err) reject(new Error(`Google returned: ${err}`));
      else if (code) resolve(code);
      else reject(new Error("no code in redirect"));
    });
  });
  return { redirect, code };
}

async function fetchUserInfo(
  accessToken: string,
): Promise<{ picture?: string; name?: string }> {
  try {
    const res = await fetch(USERINFO_URL, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (res.status < 200 || res.status >= 300) return {};
    const data = JSON.parse(await res.text()) as {
      picture?: string;
      name?: string;
    };
    return { picture: data.picture, name: data.name };
  } catch {
    return {};
  }
}

// Derive the account email from the primary calendar's id (its id == the email).
async function primaryEmail(accessToken: string): Promise<string> {
  const res = await fetch(
    "https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=owner",
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  const text = await res.text();
  if (res.status < 200 || res.status >= 300)
    throw new Error(`calendarList ${res.status}: ${text}`);
  const data = JSON.parse(text) as {
    items?: { id: string; primary?: boolean }[];
  };
  const primary = data.items?.find((c) => c.primary);
  return primary?.id ?? data.items?.[0]?.id ?? "account";
}

// Run the full consent flow: open the browser, capture the code, exchange it for
// tokens, persist the account. Resolves with the connected account email.
export async function addAccount(): Promise<string> {
  const client = loadClient();
  if (!client)
    throw new Error(
      `Missing client.json. Create ${CLIENT_FILE} with your Google OAuth ` +
        `client_id and client_secret.`,
    );

  const verifier = randomVerifier();
  const { redirect, code: codePromise } = awaitCode();
  const authUrl =
    `${AUTH_URL}?` +
    form({
      client_id: client.client_id,
      redirect_uri: redirect,
      response_type: "code",
      scope: SCOPE,
      access_type: "offline",
      prompt: "consent",
      code_challenge: challengeFor(verifier),
      code_challenge_method: "S256",
    });
  Gio.AppInfo.launch_default_for_uri(authUrl, null);

  const code = await codePromise;
  const tok = await tokenRequest({
    grant_type: "authorization_code",
    code,
    client_id: client.client_id,
    client_secret: client.client_secret,
    redirect_uri: redirect,
    code_verifier: verifier,
  });
  if (!tok.refresh_token)
    throw new Error(
      "no refresh_token returned (try removing app access in your Google account and retry)",
    );

  const email = await primaryEmail(tok.access_token);
  const info = await fetchUserInfo(tok.access_token);
  const accounts = loadAccountStore().filter((a) => a.email !== email);
  accounts.push({
    email,
    refresh: tok.refresh_token,
    access: tok.access_token,
    expiry: now() + tok.expires_in - 60,
    photo: info.picture,
    name: info.name,
  });
  saveAccountStore(accounts);
  return email;
}
