# Interactive login for the ga4 MCP server, run inside the mcp container:
#
#   podman exec -it mcp ga4-login
#
# Mirrors workspace-mcp's `workspace-<account> login`: a browser consent
# flow whose result is an authorized_user JSON persisted in the server's
# volume (/data-ga4/creds.json), so it survives container restarts and
# analytics-mcp can refresh it at runtime with no env vars.
#
# The redirect URI is http://localhost:1 — desktop clients may use any
# localhost port, and the browser will show a "connection refused" page
# whose address bar still carries the authorization code. The user pastes
# that URL (or the bare code) back here.
#
# Client credentials come from the gtm/* sops keys (same outsmartly-app
# desktop OAuth client the gtm server runs on), injected via the
# container's GA4_CLIENT_ID / GA4_CLIENT_SECRET.
import json
import os
import re
import sys
import urllib.parse
import urllib.request

SCOPES = "https://www.googleapis.com/auth/analytics.readonly"
CREDS_FILE = os.environ.get("GA4_CREDS_FILE", "/data-ga4/creds.json")
REDIRECT_URI = "http://localhost:1"


def die(msg: str) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


client_id = os.environ.get("GA4_CLIENT_ID")
client_secret = os.environ.get("GA4_CLIENT_SECRET")
if not client_id or not client_secret:
    die("GA4_CLIENT_ID / GA4_CLIENT_SECRET are not set — is this the mcp container?")

url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
    "client_id": client_id,
    "redirect_uri": REDIRECT_URI,
    "response_type": "code",
    "scope": SCOPES,
    "access_type": "offline",
    "prompt": "consent",
})

print("1. Open this URL in a browser (sign in as the account with GA access):")
print()
print(f"   {url}")
print()
print("2. After consent the browser ends up on a page that fails to load —")
print(f"   that is expected. Copy the FULL address-bar URL (it starts with {REDIRECT_URI}/?code=).")
print()
raw = input("3. Paste it here (or just the code): ").strip()

code = raw
if raw.startswith("http"):
    code = urllib.parse.parse_qs(urllib.parse.urlparse(raw).query).get("code", [""])[0]
if not code:
    die(f"no authorization code found in: {raw[:80]}…")

resp = urllib.request.urlopen(urllib.request.Request(
    "https://oauth2.googleapis.com/token",
    data=urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": REDIRECT_URI,
    }).encode(),
))
tokens = json.load(resp)
refresh_token = tokens.get("refresh_token", "")
if not re.match(r"^1//", refresh_token):
    die("Google returned no refresh token — did you re-use an old consent link? Retry with the URL above.")

creds = {
    "type": "authorized_user",
    "client_id": client_id,
    "client_secret": client_secret,
    "refresh_token": refresh_token,
}
os.makedirs(os.path.dirname(CREDS_FILE), exist_ok=True)
fd = os.open(CREDS_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(creds, f)

print(f"\nWrote {CREDS_FILE}. Restart the server to pick it up:")
print("  sudo systemctl restart podman-mcp.service")
