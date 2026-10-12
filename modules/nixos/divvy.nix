# divvy, the household bill splitting app (~/Projects/divvy), at
# divvy.<base>. The divvy flake owns the container, backups and recurring
# timers; this file picks the auth mode, pins the user's ids, and wires routing
# and receipt scanning. Assistants reach divvy's own MCP endpoint with a
# personal token made in the app, so no identity lives here.
#
# Runs as a hardened OCI container like wakapi.nix: non-root, read-only rootfs,
# no capabilities, only /var/lib/divvy (/data) writable. Traefik discovers it
# over the podman socket from the labels below and reaches its internal port
# on the podman bridge, so nothing is published to a host port.
#
# Sign-in is Cloudflare Access: cloudflared forwards the Access JWT
# (Cf-Access-Jwt-Assertion, or the CF_Authorization cookie) through traefik and
# divvy verifies it against the team's keys and this application's AUD; both
# values below are public. One account can sign in with several emails, linked
# in the app's Profile. /healthz and /mcp skip the JWT: /mcp authenticates by
# its own bearer token, and executor on this host reaches it through
# /etc/hosts → traefik without passing Cloudflare. Through Cloudflare, /mcp
# stays behind Access like the rest of the site (remote clients would add an
# Access service token, never a Bypass).
{
  flake.modules.nixos.praesidium =
    { inputs, config, ... }:
    let
      inherit (config.services.local-networking) baseDomain;
      cfg = config.services.divvy;
      subdomain = "divvy";
    in
    {
      imports = [ inputs.divvy.nixosModules.default ];

      services.divvy = {
        enable = true;
        authMode = "access";
        accessTeamDomain = "xorlop.cloudflareaccess.com";
        accessAud = "a7f161024a2a81d5cbcf9487eaff52ba460461ec70113197b563a73d0b5f23c9";
        environmentFile = config.sops.templates."divvy.env".path;
        # The ids divvy was first created with here; NixOS won't renumber an
        # existing user, and /var/lib/divvy is already owned by them.
        uid = 980;
        gid = 975;
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.divvy-secure.entrypoints" = "websecure";
          "traefik.http.routers.divvy-secure.rule" = "Host(`${subdomain}.${baseDomain}`)";
          "traefik.http.routers.divvy-secure.tls" = "true";
          "traefik.http.routers.divvy-secure.tls.certResolver" = "cloudflare";
          "traefik.http.routers.divvy-secure.service" = "divvy-svc";
          "traefik.http.services.divvy-svc.loadbalancer.server.port" = toString cfg.port;
        };
      };

      # /etc/hosts entry + the mkcert cert SAN, like every traefik-fronted service.
      services.local-networking.subdomains = [ subdomain ];

      # Receipt scanning runs `claude -p` on the subscription token the agent
      # MCP already uses.
      sops.secrets."claude/oauth_token" = { };
      sops.templates."divvy.env" = {
        content = "CLAUDE_CODE_OAUTH_TOKEN=${config.sops.placeholder."claude/oauth_token"}";
        restartUnits = [ "podman-divvy.service" ];
      };
    };
}
