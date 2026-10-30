# rcsd: the Google Messages (SMS/RCS) backend from the xav-ie/rcsd fork of
# OpenMessage, and rcsd-web, its static web client, on praesidium. Both run
# as hardened OCI containers (like modules/nixos/wakapi.nix) from images built
# here with dockerTools, and publish no host port: traefik reaches them on the
# podman bridge. One host, split by path:
#
#   https://messages.<baseDomain>/{api,mcp,auth}  -> rcsd (port 7007)
#   https://messages.<baseDomain>/*               -> rcsd-web (static files)
#
# messages.<baseDomain> has its own Cloudflare record (a tunnel route behind
# Cloudflare Access, managed in the dashboard), so off this host it is public
# behind Access rather than on the tailnet wildcard; on praesidium it resolves
# to loopback. Every request still needs the bearer token
# (OPENMESSAGES_AUTH_MODE=enforce), MCP clients included; rcsd-web sends the
# Access cookie along since it is same-origin. rcsd mints it
# on first start as /var/lib/rcsd/control.token (0600, uid 7007); nox's data
# dir already carries one, so the migrated token keeps working.
#
# The rcsd router carries no compress middleware: traefik's compress only
# skips text/event-stream when the *request* says so, which an EventSource
# GET never does, so it would gzip and hold back /api/events (SSE). Traefik
# adds no response buffering of its own.
#
# Enabled on praesidium after the migration from nox. To migrate again, first copy
# nox's data dir with the container stopped, then hand it to the rcsd user:
#   rsync -a "nox:Library/Application Support/OpenMessage/" /var/lib/rcsd/
#   chown -R 7007:7007 /var/lib/rcsd
{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.services.local-networking) baseDomain;
      cfg = config.services.rcsd;
      fullHostName = "${cfg.subdomain}.${baseDomain}";
      dataDir = "/var/lib/rcsd";
      # Pinned so the container and the /data volume agree.
      uid = 7007;
      port = 7007;
      webPort = 8080;

      image = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/rcsd";
        tag = "latest";
        contents = [ pkgs.cacert ];
        config = {
          Cmd = [
            (lib.getExe pkgs.pkgs-mine.rcsd)
            "serve"
            "--web"
            "--mcp-sse"
          ];
          Env = [
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            # MCP results show local timestamps, as on nox.
            "TZ=${config.time.timeZone}"
            "ZONEINFO=${pkgs.tzdata}/share/zoneinfo"
          ];
        };
      };

      webImage = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/rcsd-web";
        tag = "latest";
        config.Cmd = [
          (lib.getExe pkgs.miniserve)
          "--interfaces"
          "0.0.0.0"
          "--port"
          (toString webPort)
          "--index"
          "index.html"
          # The client routes by path (/c/<id>), so unknown paths get
          # index.html; no directory listings.
          "--spa"
          "--disable-indexing"
          "${cfg.webRoot}"
        ];
      };

      # The same containment for both containers: unprivileged, read-only,
      # no capabilities, no privilege escalation.
      hardening = [
        "--user=${toString uid}:${toString uid}"
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=64m"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--no-healthcheck"
      ];

      router = name: rule: {
        "traefik.enable" = "true";
        "traefik.http.routers.${name}.entrypoints" = "websecure";
        "traefik.http.routers.${name}.rule" = rule;
        "traefik.http.routers.${name}.tls" = "true";
        "traefik.http.routers.${name}.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${name}.service" = "${name}-svc";
      };
    in
    {
      options.services.rcsd = {
        enable = lib.mkEnableOption "rcsd and rcsd-web behind traefik";

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "messages";
          description = "Subdomain under the base domain that traefik routes to rcsd and rcsd-web.";
        };

        webRoot = lib.mkOption {
          type = lib.types.package;
          default = pkgs.pkgs-mine.rcsd-web;
          defaultText = lib.literalExpression "pkgs.pkgs-mine.rcsd-web";
          description = ''
            Built rcsd-web static site to serve at the domain root: the Astro
            dist/ directory, index.html plus hashed /_astro/* assets.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Adds the /etc/hosts entry and the cert SAN, like wakapi.
        services.local-networking.subdomains = [ cfg.subdomain ];

        users.users.rcsd = {
          isSystemUser = true;
          group = "rcsd";
          inherit uid;
        };
        users.groups.rcsd.gid = uid;

        systemd.tmpfiles.rules = [ "d ${dataDir} 0700 rcsd rcsd -" ];

        virtualisation.oci-containers.containers.rcsd = {
          imageFile = image;
          image = "localhost/rcsd:latest";
          autoStart = true;
          volumes = [ "${dataDir}:/data" ];
          environment = {
            # Anything resolved under $HOME (exports) stays on the volume.
            HOME = "/data";
            OPENMESSAGES_DATA_DIR = "/data";
            OPENMESSAGES_HOST = "0.0.0.0";
            OPENMESSAGES_PORT = toString port;
            OPENMESSAGES_AUTH_MODE = "enforce";
            OPENMESSAGES_ALLOWED_HOSTS = fullHostName;
            # traefik terminates TLS, so the browser's same-origin requests
            # arrive with this Origin.
            OPENMESSAGES_CORS_ORIGINS = "https://${fullHostName}";
            OPENMESSAGES_LOG_LEVEL = "info";
            # Your name on your own messages. Without it the backend uses the
            # account's full name: nox's RealName, but nothing here.
            OPENMESSAGES_MY_NAME = "Xavier Ruiz";
            # nox's store was migrated to v2 (`openmessage migrate`).
            OPENMESSAGES_V2_PRIMARY = "1";
          };
          extraOptions = hardening;
          labels =
            router "rcsd-secure" "Host(`${fullHostName}`) && (PathPrefix(`/api`) || PathPrefix(`/mcp`) || PathPrefix(`/auth`))"
            // {
              "traefik.http.routers.rcsd-secure.priority" = "100";
              "traefik.http.services.rcsd-secure-svc.loadbalancer.server.port" = toString port;
            };
        };

        virtualisation.oci-containers.containers.rcsd-web = {
          imageFile = webImage;
          image = "localhost/rcsd-web:latest";
          autoStart = true;
          extraOptions = hardening;
          # index.html is revalidated on every load so a deploy shows at once;
          # the hashed /_astro/* assets never change, so they cache for a year.
          labels =
            router "rcsd-web-secure" "Host(`${fullHostName}`)"
            // router "rcsd-web-assets" "Host(`${fullHostName}`) && PathPrefix(`/_astro/`)"
            // {
              "traefik.http.routers.rcsd-web-secure.priority" = "1";
              "traefik.http.routers.rcsd-web-secure.middlewares" = "compress@file,rcsd-web-no-cache";
              "traefik.http.routers.rcsd-web-assets.priority" = "50";
              "traefik.http.routers.rcsd-web-assets.middlewares" = "compress@file,rcsd-web-immutable";
              "traefik.http.routers.rcsd-web-assets.service" = "rcsd-web-secure-svc";
              "traefik.http.middlewares.rcsd-web-no-cache.headers.customresponseheaders.Cache-Control" =
                "no-cache";
              "traefik.http.middlewares.rcsd-web-immutable.headers.customresponseheaders.Cache-Control" =
                "public, max-age=31536000, immutable";
              "traefik.http.services.rcsd-web-secure-svc.loadbalancer.server.port" = toString webPort;
            };
        };
      };
    };
}
