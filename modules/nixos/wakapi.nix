# Wakapi — self-hosted, WakaTime-compatible backend for praesidium.
#
# The WakaTime clients wired up in modules/wakatime.nix (the VS Code extension,
# the macOS menu-bar app, the Claude Code plugin) all POST heartbeats to
# whatever `api_url` sits in ~/.wakatime.cfg. Point that at this instance and
# the coding stats stay on our own hardware instead of wakatime.com.
#
# Runs as a hardened OCI container (like modules/nixos/llama-server.nix) rather
# than a host service: wakapi's /api path is exposed to the public internet
# through a Cloudflare Access *bypass* (the CLI authenticates with an API key and
# can't complete interactive SSO), so an /api exploit should be contained to a
# throwaway namespace, not the host. The container drops all capabilities, runs
# read-only as a non-root uid, and only its /data volume is writable.
#
# Traefik fronts it: praesidium's traefik (a host service with `group = podman`)
# discovers the container over the podman socket via the `traefik.enable` labels
# below and reaches its internal port on the podman bridge — so nothing is
# published to a host port; the only ingress is traefik.
#
# The Cloudflare Tunnel ingress and the Access application themselves are
# dashboard-managed (same as muscat/postiz), so they live outside this repo:
#   1. Tunnel ingress: route wakapi.lalala.casa -> https://<praesidium LAN>:443
#      (traefik), Origin Server Name `wakapi.lalala.casa`.
#   2. Access: SSO-protect the hostname for the dashboard UI, but add a *bypass*
#      (or Service Auth) policy on path /api/** — the WakaTime CLI authenticates
#      with wakapi's own API key and cannot complete interactive Access SSO.
#
# Declarative account (why the seed unit below exists): wakapi ships no
# user-management CLI or env bootstrap — the only built-in way to make a user is
# the signup form, which mints a *random* api key, so a nuked-then-rebuilt host
# would lose the account and every client's key. `wakapi-seed` instead reconciles
# the account straight into wakapi's sqlite `users` table from sops (pinned
# username + password + api_key), idempotently, so `just system` fully recreates
# it. The seed and the clients (modules/wakatime.nix) read the *same*
# `wakapi/api_key` secret — one source of truth, so the editors never need
# reconfiguring and the account key can't drift into a 401. It runs
# on the host against the bind-mounted DB file — wakapi's static binary uses a
# standard-format sqlite database, so the host `sqlite3` CLI reads/writes the
# same file. `allow_signup` stays false. This couples to a few stable `users`
# columns; if a future wakapi changes them the oneshot fails loudly on switch
# rather than silently corrupting anything.
#
# Secrets (add once with `sops secrets/main.yaml`, then `just system`):
#   wakapi:
#     password_salt: <random>       # pepper for password hashing (WAKAPI_PASSWORD_SALT)
#     username: <you>               # dashboard login + primary key of the row
#     password: <your password>     # dashboard login password
#     api_key:  <a uuid>            # bearer token; seeded into the account AND
#                                   #   rendered into ~/.wakatime.cfg by the clients
# None of these land in the world-readable store.
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
      cfg = config.services.wakapi;
      fullHostName = "${cfg.subdomain}.${baseDomain}";
      dataDir = "/var/lib/wakapi";
      dbPath = "${dataDir}/wakapi.db";
      # wakapi's image is FROM gcr.io/distroless/static:nonroot, whose non-root
      # user is uid/gid 65532. Pin a matching static host user so the container,
      # the bind-mounted /data, and the host-side seed all agree on ownership.
      wUid = 65532;
      # wakapi listens on this port *inside* the container; traefik reaches it on
      # the podman bridge, so it's never bound on the host.
      containerPort = 3000;
    in
    {
      options.services.wakapi.subdomain = lib.mkOption {
        type = lib.types.str;
        default = "wakapi";
        description = "Subdomain under the base domain that traefik routes to wakapi.";
      };

      config = {
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
        };

        # Register the subdomain: adds the /etc/hosts entry + the mkcert cert
        # SAN, same as every other traefik-fronted service here.
        services.local-networking.subdomains = [ cfg.subdomain ];

        users.users.wakapi = {
          isSystemUser = true;
          group = "wakapi";
          uid = wUid;
        };
        users.groups.wakapi.gid = wUid;

        systemd.tmpfiles.rules = [
          "d ${dataDir} 0700 wakapi wakapi -"
        ];

        sops.secrets = {
          # Rendered into the wakapi.env template placeholder below (never a
          # standalone file on disk).
          "wakapi/password_salt" = { };
          # Read by the seed unit (running as the wakapi user), so grant it.
          "wakapi/username".owner = "wakapi";
          "wakapi/password".owner = "wakapi";
          # api_key is the single source of truth, shared by two readers: the
          # seed (this host, as the wakapi user) reconciles the account to it,
          # and the clients (modules/wakatime.nix, as the human user) render it
          # into ~/.wakatime.cfg. modules/wakatime.nix owns it (owner =
          # defaultUser); here we only add group-read for the seed's wakapi user.
          "wakapi/api_key" = {
            group = "wakapi";
            mode = lib.mkForce "0440";
          };
        };
        sops.templates."wakapi.env" = {
          # WAKAPI_PASSWORD_SALT is the pepper wakapi mixes into every password
          # hash; injected as an env var so it never lands in a world-readable
          # store path. Read by the container (env-file) and the seed (which must
          # compute a hash that verifies against wakapi's login), so grant wakapi.
          owner = "wakapi";
          content = "WAKAPI_PASSWORD_SALT=${config.sops.placeholder."wakapi/password_salt"}";
          restartUnits = [
            "podman-wakapi.service"
            "wakapi-seed.service"
          ];
        };

        virtualisation.oci-containers.containers.wakapi = {
          image = "ghcr.io/muety/wakapi:2.16.1";
          autoStart = true;
          volumes = [
            "${dataDir}:/data"
          ];
          environmentFiles = [ config.sops.templates."wakapi.env".path ];
          environment = {
            WAKAPI_DB_TYPE = "sqlite3";
            WAKAPI_DB_NAME = "/data/wakapi.db";
            # wakapi's cache dir defaults under the (read-only) rootfs; point it
            # at the writable tmpfs so it stops erroring on startup.
            XDG_CACHE_HOME = "/tmp";
            WAKAPI_PORT = toString containerPort;
            WAKAPI_LISTEN_IPV4 = "0.0.0.0";
            WAKAPI_LISTEN_IPV6 = "-";
            # Canonical, TLS-terminated hostname. Drives e-mail links, avatar
            # URLs, and wakapi's own scheme decisions; the clients target it too.
            WAKAPI_PUBLIC_URL = "https://${fullHostName}";
            # The account is seeded declaratively (wakapi-seed below), so the
            # signup form is never needed. Keep it closed. (Image default: true.)
            WAKAPI_ALLOW_SIGNUP = "false";
            # Cookies always reach the browser over HTTPS (traefik + tunnel), so
            # let wakapi mark them Secure. (Image default flips this to true.)
            WAKAPI_INSECURE_COOKIES = "false";
          };
          extraOptions = [
            # Blast-radius containment for the publicly-reachable /api: run
            # unprivileged, read-only, no ambient caps, no privilege escalation.
            # Only /data (the volume) and a scratch /tmp are writable.
            "--user=${toString wUid}:${toString wUid}"
            "--read-only"
            "--tmpfs=/tmp:rw,noexec,nosuid,size=64m"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges"
            # The image's HEALTHCHECK fires immediately on `podman run`; podman
            # runs each check as a transient systemd unit whose non-zero exit
            # during the first-boot AutoMigrate would abort activation. Traefik
            # includes containers without a healthcheck, and a 502 is a loud
            # enough signal, so drop it (matches the postiz containers).
            "--no-healthcheck"
          ];
          labels = {
            "traefik.enable" = "true";
            "traefik.http.routers.wakapi-secure.entrypoints" = "websecure";
            "traefik.http.routers.wakapi-secure.rule" = "Host(`${fullHostName}`)";
            "traefik.http.routers.wakapi-secure.tls" = "true";
            "traefik.http.routers.wakapi-secure.tls.certResolver" = "cloudflare";
            "traefik.http.routers.wakapi-secure.service" = "wakapi-svc";
            "traefik.http.services.wakapi-svc.loadbalancer.server.port" = toString containerPort;
          };
        };

        # Idempotently reconcile wakapi's `users` row with sops. Runs after the
        # container so its GORM AutoMigrate has created the schema in the
        # bind-mounted DB, then talks to that sqlite file directly (wakapi ships
        # no user-management CLI). Runs as the wakapi uid the container uses so
        # any sqlite -wal/-shm files it creates stay owned consistently.
        systemd.services.wakapi-seed = {
          description = "Seed the wakapi account (idempotent) from sops";
          after = [ "podman-wakapi.service" ];
          requires = [ "podman-wakapi.service" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [
            sqlite
            libargon2 # provides the `argon2` CLI
            openssl
            coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "wakapi";
            Group = "wakapi";
            # Provides $WAKAPI_PASSWORD_SALT (the pepper) — same value the
            # container reads, so the hash we compute verifies against wakapi's
            # login.
            EnvironmentFile = config.sops.templates."wakapi.env".path;
            TimeoutStartSec = "3min";
          };
          script = ''
            set -euo pipefail

            db=${lib.escapeShellArg dbPath}
            user=$(cat ${config.sops.secrets."wakapi/username".path})
            pass=$(cat ${config.sops.secrets."wakapi/password".path})
            key=$(cat ${config.sops.secrets."wakapi/api_key".path})
            pepper="''${WAKAPI_PASSWORD_SALT:-}"

            # 1. Wait for wakapi's AutoMigrate to create the `users` table.
            for _ in $(seq 1 60); do
              if sqlite3 "$db" "SELECT 1 FROM users LIMIT 1;" >/dev/null 2>&1; then
                break
              fi
              sleep 2
            done
            # Final gate — fail the unit loudly if the schema never appeared.
            sqlite3 "$db" "SELECT 1 FROM users LIMIT 1;" >/dev/null

            # SQL single-quote escaping (double any single quote) for values
            # from sops, via bash param expansion.
            uq=''${user//\'/\'\'}
            kq=''${key//\'/\'\'}

            exists=$(sqlite3 "$db" "SELECT count(*) FROM users WHERE id = '$uq';")
            if [ "$exists" = "0" ]; then
              # argon2id of (password + pepper), matching wakapi's
              # CompareArgon2Id(plain+pepper). wakapi reads the m/t/p params back
              # out of the encoded hash, so ours only need to be valid, not equal
              # to its defaults. `-e` prints just the PHC-encoded string, which
              # is exactly what wakapi's decoder expects.
              asalt=$(openssl rand -hex 8)
              hash=$(printf '%s' "$pass$pepper" | argon2 "$asalt" -id -t 3 -m 16 -p 2 -l 32 -e)
              hq=''${hash//\'/\'\'}
              # created_at / last_logged_in_at are wakapi CustomTime columns whose
              # Scan() errors on NULL, so both MUST be set. This exact layout
              # (space + numeric offset) is one CustomTime.Scan parses.
              now=$(date -u +'%Y-%m-%d %H:%M:%S+00:00')
              email="$user@${baseDomain}"
              eq=''${email//\'/\'\'}
              sqlite3 "$db" "INSERT INTO users
                (id, api_key, password, email, is_admin, created_at, last_logged_in_at)
                VALUES ('$uq', '$kq', '$hq', '$eq', 1, '$now', '$now');"
              echo "wakapi: seeded account '$user'"
            else
              # Account already present — only re-pin the api key if it drifted
              # from sops (leave the password alone; rotate it by hand if needed).
              sqlite3 "$db" "UPDATE users SET api_key = '$kq'
                WHERE id = '$uq' AND (api_key IS NULL OR api_key <> '$kq');"
              echo "wakapi: account '$user' present; api key ensured"
            fi
          '';
        };
      };
    };
}
