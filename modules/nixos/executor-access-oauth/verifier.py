"""Traefik forwardAuth target for executor's /mcp.

Cloudflare Access (Managed OAuth) signs MCP clients in and forwards a signed
Cf-Access-Jwt-Assertion, but executor only accepts its own bearer. When the
assertion verifies for the /mcp Access app and names a user, answer with
executor's bearer; otherwise hand the client's Authorization back unchanged.
The signature check is the point: LAN clients reach traefik without passing
Access, so the header alone proves nothing.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt


def env_file_value(path, name):
    with open(path) as f:
        for line in f:
            if line.startswith(f"{name}="):
                return line.rstrip("\n").split("=", 1)[1]
    sys.exit(f"{name} missing from {path}")


ISSUER = f"https://{os.environ['CF_ACCESS_TEAM_DOMAIN']}"
AUDIENCE = os.environ["CF_ACCESS_AUD"]
BEARER = "Bearer " + env_file_value(
    os.environ["EXECUTOR_ENV_FILE"], "EXECUTOR_AUTH_TOKEN"
)
JWKS = jwt.PyJWKClient(f"{ISSUER}/cdn-cgi/access/certs", lifespan=3600)


def is_access_user(assertion):
    try:
        key = JWKS.get_signing_key_from_jwt(assertion)
        claims = jwt.decode(
            assertion,
            key.key,
            algorithms=["RS256"],
            audience=AUDIENCE,
            issuer=ISSUER,
        )
    except jwt.PyJWTError as e:
        print(f"rejected Cf-Access-Jwt-Assertion: {e}", file=sys.stderr, flush=True)
        return False
    # Service token assertions carry common_name and no email; those clients
    # already send executor's bearer themselves.
    return bool(claims.get("email"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        authorization = self.headers.get("Authorization")
        assertion = self.headers.get("Cf-Access-Jwt-Assertion")
        if assertion and is_access_user(assertion):
            authorization = BEARER
        self.send_response(200)
        if authorization:
            self.send_header("Authorization", authorization)
        self.end_headers()

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", int(os.environ["PORT"])), Handler).serve_forever()
