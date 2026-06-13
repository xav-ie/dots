# Reusable Postiz instance. Instantiated once per deployment from
# default.nix. Everything here is keyed off `name`, so each instance
# gets its own pod, containers, data dir, secrets and Temporal stack.
#
# Shared bits (the patched app image build, the overcommit sysctl) live
# in default.nix and are referenced by tag/unit name — they must NOT be
# duplicated per instance.
{
  name,
  # Public hostname. When null, falls back to `${name}.${baseDomain}`,
  # preserving the original lalala.casa behaviour for local instances.
  hostName ? null,
  # Local instances get a traefik route + a *.lalala.casa subdomain and
  # advertise themselves at the LAN IP — in this mode `hostName` must be
  # null (the route is always `${name}.${baseDomain}`; see the assertion
  # below). Tunnel instances skip traefik, publish their app port for a
  # Cloudflare Tunnel to target, and use `hostName` as the public URL.
  local ? true,
  # CPU set handed to the app container; see the cpuset rationale on the
  # container below. No default — distinct sets per instance keep them
  # from contending, and a silent default would guarantee a collision.
  cpuset ? null,
  # When non-null, publish the app port on the host (e.g.
  # "127.0.0.1:18800:5000") so a Cloudflare Tunnel can target it.
  publishPort ? null,
  # Whether to wire up the social-provider OAuth secrets + env. Only the
  # original instance has these configured today.
  enableSocialProviders ? false,
  # Patched copy of the app image's nginx.conf, mounted over the baked one so
  # its `proxy_pass` upstreams use 127.0.0.1 instead of `localhost` (which the
  # pod resolves to IPv6 `::1`, where the IPv4-only node backends aren't
  # listening → 502). Built in default.nix from the source config.
  nginxConf,
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  subdomain = name;
  fullHostName =
    if hostName != null then hostName else "${name}.${config.services.local-networking.baseDomain}";

  postizDataDir = "/var/lib/${name}";
  postgresUser = "${subdomain}-user";
  postgresDB = "${subdomain}-db-local";

  # UID/GID of postgres user inside postgres:17-alpine container
  # To verify/update: podman run --rm postgres:17-alpine id postgres
  # Alpine Linux uses UID 70 as the standard for the postgres system user
  postgresUID = "70";
  postgresGID = "70";

  # UID/GID of redis user inside redis:7.2 container
  # To verify/update: podman run --rm redis:7.2 id redis
  redisUID = "999";
  redisGID = "999";

  # UID/GID of postgres user inside postgres:16 (Debian) container
  # Used for the Temporal-backing postgres only.
  temporalPgUID = "999";
  temporalPgGID = "999";

  cfgSecret = config.sops.placeholder;

  # Postiz records each upload's URL as `${FRONTEND_URL}/uploads/...`
  # (local.storage.ts) and every social provider re-fetches that URL to upload
  # the media bytes. FRONTEND_URL is the public, Cloudflare-Access-fronted
  # hostname, so the fetch would otherwise leave the pod and hit the Access
  # edge. This preload rewrites upload reads to the in-pod origin, keeping
  # media local so `/uploads/*` stays behind Access. Keyed off FRONTEND_URL so
  # it tracks the env across Postiz upgrades.
  #
  # Two transports need rewriting: `globalThis.fetch` (some video paths) and
  # axios. The image providers — X and LinkedIn via `readOrFetch`, Bluesky
  # directly — download bytes with axios, which bypasses the fetch override, so
  # we also add a request interceptor on the default axios instance as it loads.
  uploadFetchShim = pkgs.writeText "postiz-upload-fetch-shim.cjs" ''
    const orig = globalThis.fetch;
    const PUB = (process.env.FRONTEND_URL || "") + "/uploads";
    const INT = "http://127.0.0.1:5000/uploads";
    const rewrite = (u) =>
      typeof u === "string" && u.startsWith(PUB) ? INT + u.slice(PUB.length) : u;

    globalThis.fetch = (input, init) => {
      if (typeof input === "string") {
        input = rewrite(input);
      } else if (input && typeof input.url === "string" && input.url.startsWith(PUB)) {
        input = new Request(rewrite(input.url), input);
      }
      return orig(input, init);
    };

    const Module = require("module");
    const origLoad = Module._load;
    Module._load = function (request, parent, isMain) {
      const mod = origLoad.apply(this, arguments);
      try {
        if (request === "axios") {
          const ax = mod && mod.default ? mod.default : mod;
          if (ax && ax.interceptors && !ax.__uploadShim) {
            ax.__uploadShim = true;
            ax.interceptors.request.use((config) => {
              if (config && typeof config.url === "string") {
                config.url = rewrite(config.url);
              }
              return config;
            });
          }
        }
      } catch (_e) {}
      return mod;
    };
  '';

  # Pinned tags for the temporal stack. Server + admin-tools follow
  # `temporalio/temporal` releases; we picked the latest 1.30 minor that
  # was published when this config was written. Bump together.
  temporalServerImage = "docker.io/temporalio/server:1.30.4";
  temporalAdminToolsImage = "docker.io/temporalio/admin-tools:1.30";

  # Dynamicconfig file (runtime feature toggles). The server refuses to
  # start without one when DYNAMIC_CONFIG_FILE_PATH is set.
  #
  # Beyond the required maxIDLength, every knob here trims Temporal's idle
  # background CPU for this very-low-throughput deployment (a handful of
  # scheduled-post workflows). Temporal's defaults assume a busy cluster:
  # each task queue gets 4 read + 4 write partitions that the matching
  # service long-polls continuously, and the history queue processors poll
  # on a tight interval. Three things drive the idle DB churn:
  #   - matching partitions (4 read + 4 write) each long-poll the queue;
  #   - each history queue processor (timer/transfer/visibility) polls for
  #     new tasks on a tight interval AND checkpoints its ack level to the
  #     DB every 30s (UpdateAckInterval), a steady write even at zero load;
  #   - matching long-polls expire every 60s, re-reading the queue each time.
  # Collapsing partitions to 1, stretching every processor poll to 5m,
  # stretching the ack-level checkpoints to 5m, and lengthening the matching
  # long-poll to 5m removes nearly all of the idle churn with no behavioural
  # change at our volume (scheduled posts still fire on time — a new task
  # signals the processor directly rather than waiting for the next poll).
  temporalDynamicConfig = pkgs.writeText "temporal-dynamicconfig.yaml" ''
    limit.maxIDLength:
      - value: 255
        constraints: {}
    matching.numTaskqueueReadPartitions:
      - value: 1
        constraints: {}
    matching.numTaskqueueWritePartitions:
      - value: 1
        constraints: {}
    matching.longPollExpirationInterval:
      - value: "5m"
        constraints: {}
    history.timerProcessorMaxPollInterval:
      - value: "5m"
        constraints: {}
    history.transferProcessorMaxPollInterval:
      - value: "5m"
        constraints: {}
    history.visibilityProcessorMaxPollInterval:
      - value: "5m"
        constraints: {}
    history.timerProcessorUpdateAckInterval:
      - value: "5m"
        constraints: {}
    history.transferProcessorUpdateAckInterval:
      - value: "5m"
        constraints: {}
    history.visibilityProcessorUpdateAckInterval:
      - value: "5m"
        constraints: {}
  '';

  socialEnv =
    lib.optionalString enableSocialProviders # sh
      ''

        # mastodon
        MASTODON_CLIENT_ID=${cfgSecret."${name}/mastodon/client_id"}
        MASTODON_CLIENT_SECRET=${cfgSecret."${name}/mastodon/client_secret"}
        MASTODON_URL=https://mastodon.social

        # linkedin
        LINKEDIN_CLIENT_ID=${cfgSecret."${name}/linkedin/client_id"}
        LINKEDIN_CLIENT_SECRET=${cfgSecret."${name}/linkedin/client_secret"}

        # x
        X_API_KEY=${cfgSecret."${name}/x/api_key"}
        X_API_SECRET=${cfgSecret."${name}/x/api_key_secret"}

        # discord
        DISCORD_CLIENT_ID=${cfgSecret."${name}/discord/client_id"}
        DISCORD_CLIENT_SECRET=${cfgSecret."${name}/discord/client_secret"}
        DISCORD_BOT_TOKEN_ID=${cfgSecret."${name}/discord/bot_token"}

        # slack
        SLACK_ID=${cfgSecret."${name}/slack/client_id"}
        SLACK_SECRET=${cfgSecret."${name}/slack/client_secret"}
      '';
in
{
  config = {
    assertions = [
      {
        assertion =
          !local || hostName == null || hostName == "${name}.${config.services.local-networking.baseDomain}";
        message =
          "postiz instance '${name}': local=true requires hostName to be null or "
          + "'${name}.${config.services.local-networking.baseDomain}' (traefik routes "
          + "by hostName but the cert + /etc/hosts entry track the subdomain name).";
      }
    ];

    sops = {
      secrets = {
        # internal
        "${name}/internal/jwt_secret" = { };
        "${name}/internal/postgres_password" = { };
      }
      // lib.optionalAttrs enableSocialProviders {
        # linkedin
        "${name}/linkedin/client_id" = { };
        "${name}/linkedin/client_secret" = { };

        # mastodon
        "${name}/mastodon/client_id" = { };
        "${name}/mastodon/client_secret" = { };

        # x
        "${name}/x/api_key" = { };
        "${name}/x/api_key_secret" = { };

        # discord
        "${name}/discord/client_id" = { };
        "${name}/discord/client_secret" = { };
        "${name}/discord/bot_token" = { };

        # slack
        "${name}/slack/client_id" = { };
        "${name}/slack/client_secret" = { };
      };
      templates."${name}.env" = {
        mode = "0440";
        content =
          # sh
          ''
            # internal
            JWT_SECRET=${cfgSecret."${name}/internal/jwt_secret"}
            DATABASE_URL=postgresql://${postgresUser}:${
              cfgSecret."${name}/internal/postgres_password"
            }@${subdomain}-postgres:5432/${postgresDB}
          ''
          + socialEnv;
        restartUnits = [ "${subdomain}.service" ];
      };
      templates."${name}-postgres.env" = {
        mode = "0440";
        content = # sh
          ''
            POSTGRES_PASSWORD=${cfgSecret."${name}/internal/postgres_password"}
          '';
        restartUnits = [ "${subdomain}-postgres.service" ];
      };
    };

    services.local-networking.subdomains = lib.optionals local [ subdomain ];

    virtualisation.quadlet =
      let
        inherit (config.virtualisation.quadlet) pods;
      in
      {
        networks."${subdomain}-network".networkConfig = { };

        pods."${subdomain}-pod" = {
          podConfig = {
            # Local mode only: point the public hostname at the LAN IP
            # where traefik listens, so the pod reaches itself through
            # traefik. In tunnel mode there's no in-pod :443 listener,
            # so no useful target — leave DNS to resolve normally.
            addHosts = lib.optionals local [ "${fullHostName}:192.168.1.158" ];
            publishPorts = lib.optionals (publishPort != null) [ publishPort ];
          };
        };

        containers = {
          "${subdomain}-postgres" = {
            containerConfig = {
              image = "docker.io/library/postgres:17-alpine";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/postgres:/var/lib/postgresql/data"
              ];
              environmentFiles = [ config.sops.templates."${name}-postgres.env".path ];
              environments = {
                POSTGRES_USER = postgresUser;
                POSTGRES_DB = postgresDB;
              };
              # Internally-patient healthcheck: poll pg_isready for up to
              # 30s before declaring failure. Required because podman
              # fires the first healthcheck immediately on `podman run`,
              # *and* runs each check as a systemd-run transient unit
              # whose exit code propagates to journald. `--health-start-
              # period` only affects podman's failure-streak accounting,
              # not the transient's exit code — so a single non-zero
              # `pg_isready` during initdb produces a permanent "Failed
              # with result 'exit-code'" line per boot. Wrapping the
              # check in a retry loop means the transient only exits
              # non-zero when postgres is genuinely down for >30s.
              healthCmd = "sh -c 'for _ in $(seq 1 30); do pg_isready -U ${postgresUser} -d ${postgresDB} -q && exit 0; sleep 1; done; exit 1'";
              healthInterval = "60s";
              healthTimeout = "35s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
          };

          "${subdomain}-redis" = {
            containerConfig = {
              image = "docker.io/library/redis:7.2";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/redis:/data"
              ];
              healthCmd = "redis-cli ping";
              # See postiz-postgres: 30s pushes first check past startup.
              healthInterval = "30s";
              healthTimeout = "3s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
          };

          ${subdomain} = {
            containerConfig = {
              image = "localhost/postiz-app-patched:latest";
              # Disabled since we build locally for now
              # image = "ghcr.io/gitroomhq/postiz-app:latest";
              # autoUpdate = "registry";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/config:/config/"
                "${postizDataDir}/uploads:/uploads/"
                "${uploadFetchShim}:/config/upload-fetch-shim.cjs:ro"
                "${nginxConf}:/etc/nginx/nginx.conf:ro"
              ];
              environmentFiles = [ config.sops.templates."${name}.env".path ];
              environments = {
                MAIN_URL = "https://${fullHostName}";
                FRONTEND_URL = "https://${fullHostName}";
                NEXT_PUBLIC_BACKEND_URL = "https://${fullHostName}/api";
                # IPv4-explicit (127.0.0.1, not localhost) throughout: the pod
                # resolves `localhost` to IPv6 `::1`, but these services bind
                # IPv4 only, so `localhost` upstreams hang (gRPC) or are refused
                # (redis/http) → 502s. Same reason the mounted nginx.conf's
                # proxy_pass uses 127.0.0.1.
                REDIS_URL = "redis://127.0.0.1:6379";
                BACKEND_INTERNAL_URL = "http://127.0.0.1:3000";
                TEMPORAL_ADDRESS = "127.0.0.1:7233";
                IS_GENERAL = "true";
                STORAGE_PROVIDER = "local";
                UPLOAD_DIRECTORY = "/uploads";
                NEXT_PUBLIC_UPLOAD_DIRECTORY = "/uploads";
                PRISMA_HIDE_UPDATE_MESSAGE = "true";
                # Rewrite provider upload fetches to the in-pod origin; see
                # uploadFetchShim above.
                NODE_OPTIONS = "--require /config/upload-fetch-shim.cjs";
              };
              # Cap the CPU set the Temporal TS SDK sees at startup. Its Rust
              # core sizes the Tokio thread pool from `nproc`, so on a 32-thread
              # host it spawns 32 schedulers that each burn ~0.3% CPU even at
              # idle (~10% baseline). 4 cores is plenty for our throughput.
              podmanArgs = lib.optionals (cpuset != null) [ "--cpuset-cpus=${cpuset}" ];
              # No container-level healthcheck:
              #
              # - Podman fires the first healthcheck immediately when the
              #   container starts and the command exits non-zero while
              #   backend is still doing pnpm install / prisma-db-push (up
              #   to ~6 min on first boot). Even though podman ignores it
              #   (within `healthStartPeriod`), the underlying systemd-run
              #   transient unit records `status=1/FAILURE` and nh complains
              #   about it after every switch. There's no podman-side knob
              #   to skip that first check.
              # - The container runs pm2 internally, which already handles
              #   process-level restarts of orchestrator/backend/frontend.
              # - `Restart = "always"` on the systemd unit still recovers
              #   from container-level crashes.
              # Traefik returns 502 to clients while the backend isn't
              # listening — that's the loud signal that something's broken,
              # which is sufficient.
              labels = lib.optionalAttrs local {
                "traefik.enable" = "true";
                "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
                "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
                "traefik.http.routers.${subdomain}-secure.tls" = "true";
                "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
                "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
                "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "5000";
              };
            };
            serviceConfig = {
              Restart = "always";
            };
            unitConfig = {
              After = [
                "build-postiz-image.service"
                "${subdomain}-postgres.service"
                "${subdomain}-redis.service"
                "${subdomain}-temporal.service"
                "${subdomain}-temporal-namespace-init.service"
              ];
              Requires = [
                "build-postiz-image.service"
                "${subdomain}-postgres.service"
                "${subdomain}-redis.service"
                "${subdomain}-temporal.service"
                "${subdomain}-temporal-namespace-init.service"
              ];
            };
          };

          # Backing postgres for Temporal. Lives in the same pod, so we run it
          # on port 5433 to avoid colliding with postiz-postgres (5432).
          "${subdomain}-temporal-postgres" = {
            containerConfig = {
              image = "docker.io/library/postgres:16";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/temporal-postgres:/var/lib/postgresql/data"
              ];
              environments = {
                POSTGRES_PASSWORD = "temporal";
                POSTGRES_USER = "temporal";
                PGPORT = "5433";
              };
              # Internally-patient healthcheck — see the rationale on
              # postiz-postgres above. Same pattern, same reasons.
              healthCmd = "sh -c 'for _ in $(seq 1 30); do pg_isready -U temporal -p 5433 -q && exit 0; sleep 1; done; exit 1'";
              healthInterval = "60s";
              healthTimeout = "35s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
          };

          # Temporal server. Postiz connects to it via TEMPORAL_ADDRESS.
          # BIND_ON_IP=0.0.0.0 makes temporal listen on all interfaces inside
          # the pod, so other containers in the pod can reach it via localhost.
          #
          # Image is `temporalio/server` (replacement for the deprecated
          # `auto-setup` image). The server binary embeds a config template
          # and reads DB/ES connection details directly from env vars — no
          # config yaml to render. Schema setup and namespace creation are
          # handled by the two separate admin-tools oneshots below; the
          # server itself just runs `temporal-server start`.
          "${subdomain}-temporal" = {
            containerConfig = {
              image = temporalServerImage;
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${temporalDynamicConfig}:/etc/temporal/config/dynamicconfig/docker.yaml:ro"
              ];
              environments = {
                DB = "postgres12";
                DB_PORT = "5433";
                POSTGRES_USER = "temporal";
                POSTGRES_PWD = "temporal";
                POSTGRES_SEEDS = "localhost";
                # No ENABLE_ES: the server's embedded config template falls
                # back to SQL visibility on the temporal-postgres above
                # (database `temporal_visibility`, same seeds/port/creds).
                # Temporal 1.20+ supports custom search attributes on
                # PostgreSQL v12+, so Postiz's two Text attributes
                # (organizationId, postId) no longer need a search engine.
                BIND_ON_IP = "0.0.0.0";
                # One history shard instead of the default 4. Each shard runs
                # its own background queue-processing loops, so fewer shards =
                # less idle CPU; 1 is ample for our throughput. Shard count is
                # baked into cluster metadata at schema-init and CANNOT change
                # on an existing DB — the temporal-postgres volume must be
                # wiped for this to take effect (see schema-init below).
                NUM_HISTORY_SHARDS = "1";
                DYNAMIC_CONFIG_FILE_PATH = "config/dynamicconfig/docker.yaml";
                # Filter out Temporal's `info`-level startup chatter ("Not
                # enough hosts to serve the request", "shard status unknown")
                # which always fires for ~5-10s during cold start while the
                # frontend/matching/history services form their cluster ring.
                # Real problems still log at warn+.
                LOG_LEVEL = "warn";
              };
            };
            serviceConfig = {
              Restart = "always";
            };
            unitConfig = {
              After = [
                "${subdomain}-temporal-postgres.service"
                "${subdomain}-temporal-schema-init.service"
              ];
              Requires = [
                "${subdomain}-temporal-postgres.service"
                "${subdomain}-temporal-schema-init.service"
              ];
            };
          };
        };
      };

    systemd.tmpfiles.rules = [
      "d ${postizDataDir} 0755 root root -"
      "d ${postizDataDir}/postgres 0700 ${postgresUID} ${postgresGID} -"
      "d ${postizDataDir}/redis 0755 ${redisUID} ${redisGID} -"
      "d ${postizDataDir}/config 0755 root root -"
      "d ${postizDataDir}/uploads 0755 root root -"
      "d ${postizDataDir}/temporal-postgres 0700 ${temporalPgUID} ${temporalPgGID} -"
    ];

    # Schema initializer for Temporal. Sets up both the main `temporal`
    # database and the SQL `temporal_visibility` database (Postgres-backed
    # advanced visibility — no search engine). Each first-time step is
    # gated so re-runs are silent. State lives in the temporal-postgres
    # volume — wipe it to force a full re-init.
    systemd.services."${subdomain}-temporal-schema-init" = {
      description = "Initialize Temporal DB + visibility schema";
      after = [
        "${subdomain}-temporal-postgres.service"
      ];
      requires = [
        "${subdomain}-temporal-postgres.service"
      ];
      before = [ "${subdomain}-temporal.service" ];
      requiredBy = [ "${subdomain}-temporal.service" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      script = # sh
        ''
          set -eu
          PG=${subdomain}-temporal-postgres
          POD=${subdomain}-pod

          # `Requires=` only ensures the container has been started, not
          # that postgres is accepting queries. A plain TCP connect doesn't
          # trigger postgres's "FATAL: the database system is starting up"
          # log line, but pg_isready does (it sends a startup packet). Wait
          # for the socket first, then a single pg_isready as a final
          # readiness gate — by then postgres is past initdb so pg_isready
          # won't provoke the FATAL.
          for _ in $(seq 1 60); do
            if podman exec "$PG" bash -c ': </dev/tcp/localhost/5433' \
                 2>/dev/null; then
              break
            fi
            sleep 1
          done
          for _ in $(seq 1 30); do
            if podman exec "$PG" pg_isready -U temporal -p 5433 -q; then
              break
            fi
            sleep 1
          done

          # Two independent state checks. Each DB can be in an intermediate
          # state, so we gate each first-time-only `create`/`setup-schema`
          # independently (sql-tool errors if the DB exists / schema is
          # already applied). `update-schema` runs unconditionally — it's
          # idempotent and applies any new versioned migrations on a server
          # bump. The `temporal` DB is auto-created by the postgres image
          # (POSTGRES_USER=temporal); `temporal_visibility` is not, so the
          # visibility path creates it on first boot.
          if podman exec "$PG" psql -U temporal -d temporal -p 5433 -tAc \
               "SELECT 1 FROM information_schema.tables WHERE table_name='namespaces'" \
               2>/dev/null | grep -q '^1$'; then
            PG_SCHEMA_PRESENT=true
          else
            PG_SCHEMA_PRESENT=false
          fi

          if podman exec "$PG" psql -U temporal -d temporal_visibility -p 5433 -tAc \
               "SELECT 1 FROM information_schema.tables WHERE table_name='executions_visibility'" \
               2>/dev/null | grep -q '^1$'; then
            VIS_SCHEMA_PRESENT=true
          else
            VIS_SCHEMA_PRESENT=false
          fi

          echo "Temporal: pg-schema=$PG_SCHEMA_PRESENT, vis-schema=$VIS_SCHEMA_PRESENT"

          podman run --rm --pod "$POD" \
            -e PG_SCHEMA_PRESENT="$PG_SCHEMA_PRESENT" \
            -e VIS_SCHEMA_PRESENT="$VIS_SCHEMA_PRESENT" \
            -e POSTGRES_SEEDS=localhost \
            -e POSTGRES_USER=temporal \
            -e POSTGRES_PWD=temporal \
            -e SQL_PASSWORD=temporal \
            -e DB_PORT=5433 \
            ${temporalAdminToolsImage} \
            sh -eu -c '
              SQL_BASE="temporal-sql-tool --plugin postgres12 --ep $POSTGRES_SEEDS \
                -u $POSTGRES_USER -p $DB_PORT --db temporal"
              SQL_VIS="temporal-sql-tool --plugin postgres12 --ep $POSTGRES_SEEDS \
                -u $POSTGRES_USER -p $DB_PORT --db temporal_visibility"

              if [ "$PG_SCHEMA_PRESENT" != "true" ]; then
                $SQL_BASE create
                $SQL_BASE setup-schema -v 0.0
              fi
              $SQL_BASE update-schema -d /etc/temporal/schema/postgresql/v12/temporal/versioned

              if [ "$VIS_SCHEMA_PRESENT" != "true" ]; then
                $SQL_VIS create
                $SQL_VIS setup-schema -v 0.0
              fi
              $SQL_VIS update-schema -d /etc/temporal/schema/postgresql/v12/visibility/versioned
            '
        '';
    };

    # Default-namespace creator for Temporal. Runs after temporal is
    # serving — namespace creation goes through the gRPC frontend, not
    # straight into postgres.
    systemd.services."${subdomain}-temporal-namespace-init" = {
      description = "Create Temporal default namespace";
      after = [ "${subdomain}-temporal.service" ];
      requires = [ "${subdomain}-temporal.service" ];
      before = [ "${subdomain}.service" ];
      requiredBy = [ "${subdomain}.service" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Headroom for a slow cold-start boot (Temporal forms its cluster ring
        # over ~10-30s, longer under memory pressure). The health loop below is
        # the real gate; this is just the outer ceiling.
        TimeoutStartSec = "6min";
      };
      script = # sh
        ''
          set -eu
          POD=${subdomain}-pod

          podman run --rm --pod "$POD" \
            -e TEMPORAL_ADDRESS=127.0.0.1:7233 \
            -e DEFAULT_NAMESPACE=default \
            ${temporalAdminToolsImage} \
            sh -eu -c '
              for _ in $(seq 1 120); do
                if temporal operator cluster health \
                     --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
                  break
                fi
                sleep 1
              done

              if temporal operator namespace describe \
                   -n "$DEFAULT_NAMESPACE" \
                   --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
                echo "Namespace $DEFAULT_NAMESPACE already exists"
              else
                temporal operator namespace create \
                  -n "$DEFAULT_NAMESPACE" \
                  --address "$TEMPORAL_ADDRESS" \
                  --retention 24h
              fi
            '
        '';
    };
  };
}
