# Reusable Postiz instance. Instantiated once per deployment from
# default.nix. Everything here is keyed off `name`, so each instance
# gets its own pod, containers, data dir, secrets and Temporal stack.
#
# Shared bits (the patched app image build, the patched OpenSearch image
# load, the overcommit sysctl) live in default.nix and are referenced by
# tag/unit name — they must NOT be duplicated per instance.
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

  # UID/GID of the opensearch user inside opensearchproject/opensearch:3.6.0
  # (matches the `User = "1000"` on the patched image config).
  esUID = "1000";
  esGID = "1000";

  cfgSecret = config.sops.placeholder;

  # Postiz records each upload's URL as `${FRONTEND_URL}/uploads/...`
  # (local.storage.ts) and every social provider re-fetches that URL to upload
  # the media bytes. FRONTEND_URL is the public, Cloudflare-Access-fronted
  # hostname, so the fetch would otherwise leave the pod and hit the Access
  # edge. This preload rewrites upload fetches to the in-pod origin, keeping
  # media reads local so `/uploads/*` stays behind Access. Keyed off
  # FRONTEND_URL so it tracks the env across Postiz upgrades.
  uploadFetchShim = pkgs.writeText "postiz-upload-fetch-shim.cjs" ''
    const orig = globalThis.fetch;
    const PUB = (process.env.FRONTEND_URL || "") + "/uploads";
    const INT = 'http://localhost:5000/uploads';
    globalThis.fetch = (input, init) => {
      if (typeof input === 'string' && input.startsWith(PUB)) {
        input = INT + input.slice(PUB.length);
      } else if (input && typeof input.url === 'string' && input.url.startsWith(PUB)) {
        input = new Request(INT + input.url.slice(PUB.length), input);
      }
      return orig(input, init);
    };
  '';

  # Pinned tags for the temporal stack. Server + admin-tools follow
  # `temporalio/temporal` releases; we picked the latest 1.30 minor that
  # was published when this config was written. Bump together.
  temporalServerImage = "docker.io/temporalio/server:1.30.4";
  temporalAdminToolsImage = "docker.io/temporalio/admin-tools:1.30";

  # Minimal dynamicconfig file (runtime feature toggles). The server
  # refuses to start without one when DYNAMIC_CONFIG_FILE_PATH is set.
  # Values mirror temporalio/samples-server's development-sql.yaml; the
  # stamp comment is just to keep the file non-empty/readable.
  temporalDynamicConfig = pkgs.writeText "temporal-dynamicconfig.yaml" ''
    limit.maxIDLength:
      - value: 255
        constraints: {}
  '';

  # OpenSearch 3.6.0's image ships the performance-analyzer agent but
  # not its config file. Without one, the agent logs two ERRORs at
  # boot before disabling itself. Mount this stub at the expected path
  # to keep startup quiet.
  opensearchPerfAnalyzerConfig = pkgs.writeText "performance-analyzer.properties" ''
    webservice-bind-host = 127.0.0.1
    webservice-port = 9600
    metrics-location = /dev/shm/performanceanalyzer/
    metrics-deletion-interval = 1
    https-enabled = false
    plugin-stats-metadata = plugin-stats-metadata
    agent-stats-metadata = agent-stats-metadata
  '';

  # The OpenSearch image (with jvm.options patched) is built and loaded
  # by temporal-opensearch-image.nix; this string is the tag the load
  # service registers, kept here so the container ref agrees.
  opensearchPatchedImageRef = "localhost/postiz-temporal-opensearch:patched";

  socialEnv = lib.optionalString enableSocialProviders ''

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
              ];
              environmentFiles = [ config.sops.templates."${name}.env".path ];
              environments = {
                MAIN_URL = "https://${fullHostName}";
                FRONTEND_URL = "https://${fullHostName}";
                NEXT_PUBLIC_BACKEND_URL = "https://${fullHostName}/api";
                REDIS_URL = "redis://localhost:6379";
                BACKEND_INTERNAL_URL = "http://localhost:3000";
                TEMPORAL_ADDRESS = "localhost:7233";
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

          # OpenSearch backs Temporal's "advanced visibility". Postiz
          # registers >3 Text-type custom search attributes per workflow,
          # which exceeds SQL visibility's per-type column limit, so we
          # need a search-capable visibility store. OpenSearch speaks the
          # Elasticsearch v7 protocol; Temporal's ES_VERSION=v7 + the
          # `temporal-elasticsearch-tool` from admin-tools both work
          # against it unmodified. Image and tunables track the
          # samples-server postgres-opensearch compose example.
          "${subdomain}-temporal-opensearch" = {
            containerConfig = {
              # OpenSearch 3.x runs on Java 21 (no more SecurityManager)
              # and Lucene 10. The protocol stays ES 7.10-compatible for
              # clients, so Temporal's ES_VERSION=v7 + admin-tools'
              # temporal-elasticsearch-tool keep working unmodified.
              # Lucene index format changed though, so the on-disk data
              # dir must be wiped when crossing 2.x → 3.x.
              # We don't pull the upstream tag here — the load service
              # above sideloads our locally-patched copy with the
              # jvm.options noise stripped.
              image = opensearchPatchedImageRef;
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/temporal-opensearch:/usr/share/opensearch/data"
                "${opensearchPerfAnalyzerConfig}:/usr/share/opensearch/config/opensearch-performance-analyzer/performance-analyzer.properties:ro"
              ];
              environments = {
                "cluster.routing.allocation.disk.threshold_enabled" = "true";
                "cluster.routing.allocation.disk.watermark.low" = "512mb";
                "cluster.routing.allocation.disk.watermark.high" = "256mb";
                "cluster.routing.allocation.disk.watermark.flood_stage" = "128mb";
                "discovery.type" = "single-node";
                # OpenSearch 3.x dropped SecurityManager entirely, so
                # the `-Djava.security.manager=allow` flag we needed on
                # 2.x is no longer applicable. Keeping the locale +
                # native-access flags for the JVM-level warnings that
                # would otherwise still fire on Java 21.
                OPENSEARCH_JAVA_OPTS = "-Xms256m -Xmx256m -Djava.locale.providers=CLDR --enable-native-access=ALL-UNNAMED";
                # OpenSearch's bundled security plugin is unnecessary for
                # a single-node, pod-local visibility store.
                "plugins.security.disabled" = "true";
                # 2.12+ runs the demo-config installer at every boot and
                # refuses to start without OPENSEARCH_INITIAL_ADMIN_PASSWORD,
                # even when the security plugin is disabled at runtime.
                # Skipping the installer entirely avoids both the password
                # requirement and the demo certs we'd never use.
                DISABLE_INSTALL_DEMO_CONFIG = "true";
              };
              # OpenSearch refuses to start without the higher fd limit.
              podmanArgs = [ "--ulimit=nofile=65536:65536" ];
              # Internally-patient healthcheck — see the rationale on
              # postiz-postgres. OpenSearch boot is ~30-40s on this host,
              # so the inner loop has a 60s budget before declaring real
              # failure.
              healthCmd = "sh -c 'for _ in $(seq 1 60); do curl -fsS http://localhost:9200/_cluster/health >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
              healthInterval = "120s";
              healthTimeout = "65s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
            unitConfig = {
              After = [ "load-postiz-temporal-opensearch-image.service" ];
              Requires = [ "load-postiz-temporal-opensearch-image.service" ];
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
                ENABLE_ES = "true";
                ES_SEEDS = "localhost";
                ES_VERSION = "v7";
                BIND_ON_IP = "0.0.0.0";
                DYNAMIC_CONFIG_FILE_PATH = "config/dynamicconfig/docker.yaml";
                # Filter out Temporal's `info`-level startup chatter
                # ("Not enough hosts to serve the request", "shard status
                # unknown", "matching client encountered error") which
                # always fires for ~5-10s during cold start while the
                # frontend/matching/history services are forming their
                # internal cluster ring. Real problems still log at warn+.
                LOG_LEVEL = "warn";
              };
            };
            serviceConfig = {
              Restart = "always";
            };
            unitConfig = {
              After = [
                "${subdomain}-temporal-postgres.service"
                "${subdomain}-temporal-opensearch.service"
                "${subdomain}-temporal-schema-init.service"
              ];
              Requires = [
                "${subdomain}-temporal-postgres.service"
                "${subdomain}-temporal-opensearch.service"
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
      "d ${postizDataDir}/temporal-opensearch 0750 ${esUID} ${esGID} -"
    ];

    # Schema/index initializer for Temporal. Skips entirely when the
    # `namespaces` table is already present, so re-runs are silent.
    # State lives in the postgres/ES volumes — wipe those to force a
    # full re-init.
    systemd.services."${subdomain}-temporal-schema-init" = {
      description = "Initialize Temporal DB schema + ES indexes";
      after = [
        "${subdomain}-temporal-postgres.service"
        "${subdomain}-temporal-opensearch.service"
      ];
      requires = [
        "${subdomain}-temporal-postgres.service"
        "${subdomain}-temporal-opensearch.service"
      ];
      before = [ "${subdomain}-temporal.service" ];
      requiredBy = [ "${subdomain}-temporal.service" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      script = ''
        set -eu
        PG=${subdomain}-temporal-postgres
        OS=${subdomain}-temporal-opensearch
        POD=${subdomain}-pod

        # `Requires=` only ensures the containers have been started, not
        # that postgres is accepting queries or that OpenSearch is bound
        # on :9200. OpenSearch boot is the long pole (~30-40s on this
        # host), so its loop has the larger budget.
        #
        # For postgres: a plain TCP connect doesn't trigger postgres's
        # "FATAL: the database system is starting up" log line, but
        # pg_isready does (it sends a startup packet). Wait for the
        # socket first, then a single pg_isready as a final readiness
        # gate — by then postgres is past initdb so pg_isready won't
        # provoke the FATAL.
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

        for _ in $(seq 1 90); do
          if podman exec "$OS" \
               curl -fsS "http://localhost:9200/_cluster/health" \
               >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # Two independent state checks. Either side can be in an
        # intermediate state (e.g. postgres got migrated past failure
        # but ES never got its index), so we gate each first-time-only
        # operation independently:
        #   - PG_SCHEMA_PRESENT: skip `create` + `setup-schema -v 0.0`
        #     (sql-tool errors if DB exists / schema already applied)
        #   - ES_INDEX_PRESENT:  skip `create-index`
        #     (errors with "already exists")
        # Always-safe operations (`update-schema`, ES `setup-schema`)
        # run unconditionally — both are idempotent and apply any new
        # versioned migrations on a server bump.
        if podman exec "$PG" psql -U temporal -d temporal -p 5433 -tAc \
             "SELECT 1 FROM information_schema.tables WHERE table_name='namespaces'" \
             2>/dev/null | grep -q '^1$'; then
          PG_SCHEMA_PRESENT=true
        else
          PG_SCHEMA_PRESENT=false
        fi

        if podman exec "$OS" curl -fsS -o /dev/null \
             "http://localhost:9200/temporal_visibility_v1_dev" \
             2>/dev/null; then
          ES_INDEX_PRESENT=true
        else
          ES_INDEX_PRESENT=false
        fi

        echo "Temporal: pg-schema=$PG_SCHEMA_PRESENT, es-index=$ES_INDEX_PRESENT"

        podman run --rm --pod "$POD" \
          -e PG_SCHEMA_PRESENT="$PG_SCHEMA_PRESENT" \
          -e ES_INDEX_PRESENT="$ES_INDEX_PRESENT" \
          -e POSTGRES_SEEDS=localhost \
          -e POSTGRES_USER=temporal \
          -e POSTGRES_PWD=temporal \
          -e SQL_PASSWORD=temporal \
          -e DB_PORT=5433 \
          -e ES_SCHEME=http \
          -e ES_HOST=localhost \
          -e ES_PORT=9200 \
          -e ES_VERSION=v7 \
          -e ES_VISIBILITY_INDEX=temporal_visibility_v1_dev \
          ${temporalAdminToolsImage} \
          sh -eu -c '
            SQL_BASE="temporal-sql-tool --plugin postgres12 --ep $POSTGRES_SEEDS \
              -u $POSTGRES_USER -p $DB_PORT --db temporal"
            ES_EP="$ES_SCHEME://$ES_HOST:$ES_PORT"

            if [ "$PG_SCHEMA_PRESENT" != "true" ]; then
              $SQL_BASE create
              $SQL_BASE setup-schema -v 0.0
            fi
            $SQL_BASE update-schema -d /etc/temporal/schema/postgresql/v12/temporal/versioned

            temporal-elasticsearch-tool --ep "$ES_EP" setup-schema
            if [ "$ES_INDEX_PRESENT" != "true" ]; then
              temporal-elasticsearch-tool --ep "$ES_EP" create-index --index "$ES_VISIBILITY_INDEX"
            fi
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
        TimeoutStartSec = "3min";
      };
      script = ''
        set -eu
        POD=${subdomain}-pod

        podman run --rm --pod "$POD" \
          -e TEMPORAL_ADDRESS=localhost:7233 \
          -e DEFAULT_NAMESPACE=default \
          ${temporalAdminToolsImage} \
          sh -eu -c '
            for _ in $(seq 1 60); do
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
