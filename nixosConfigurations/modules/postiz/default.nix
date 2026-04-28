{
  config,
  inputs,
  pkgs,
  ...
}:

let
  subdomain = "postiz";
  inherit (config.services.local-networking) baseDomain;
  fullHostName = "${subdomain}.${baseDomain}";

  postizDataDir = "/var/lib/postiz";
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

  # UID/GID of elasticsearch user inside elasticsearch:7.17 container.
  esUID = "1000";
  esGID = "1000";

  cfgSecret = config.sops.placeholder;

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
  # by postiz-temporal-opensearch-image.nix; this string is the tag the
  # load service registers, kept here so the container ref agrees.
  opensearchPatchedImageRef = "localhost/postiz-temporal-opensearch:patched";

  # Fetch and patch the Postiz source.
  #
  # Source comes from the `postiz-src` flake input, currently pointed at
  # a local clone (~/Projects/postiz-app) while we test the
  # `fix(mastra): use dedicated postgres schema` change. Once upstream
  # accepts the fix and ships a release, swap the input back to a github
  # ref in flake.nix.
  postizSrc = pkgs.stdenv.mkDerivation {
    name = "postiz-src-patched";
    src = inputs.postiz-src;
    patches = [
      ./integration-fix.patch
      ./pm2-quiet.patch
    ];
    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./temporal-opensearch-image.nix
  ];

  config = {
    # Systemd service to build the Docker image from patched source
    systemd.services."build-${subdomain}-image" = {
      description = "Build patched Docker image";
      wantedBy = [ "multi-user.target" ];
      before = [ "${subdomain}.service" ];
      path = with pkgs; [ podman ];

      script = ''
        # Build the Docker image using the patched source and Dockerfile.dev
        podman build -f ${postizSrc}/Dockerfile.dev -t localhost/postiz-app-patched:latest ${postizSrc}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    sops = {
      secrets = {
        # internal
        "postiz/internal/jwt_secret" = { };
        "postiz/internal/postgres_password" = { };

        # linkedin
        "postiz/linkedin/client_id" = { };
        "postiz/linkedin/client_secret" = { };

        # mastodon
        "postiz/mastodon/client_id" = { };
        "postiz/mastodon/client_secret" = { };

        # x
        "postiz/x/api_key" = { };
        "postiz/x/api_key_secret" = { };

        # discord
        "postiz/discord/client_id" = { };
        "postiz/discord/client_secret" = { };
        "postiz/discord/bot_token" = { };

        # slack
        "postiz/slack/client_id" = { };
        "postiz/slack/client_secret" = { };
      };
      templates."postiz.env" = {
        mode = "0440";
        content =
          # sh
          ''
            # internal
            JWT_SECRET=${cfgSecret."postiz/internal/jwt_secret"}
            DATABASE_URL=postgresql://${postgresUser}:${
              cfgSecret."postiz/internal/postgres_password"
            }@${subdomain}-postgres:5432/${postgresDB}

            # mastodon
            MASTODON_CLIENT_ID=${cfgSecret."postiz/mastodon/client_id"}
            MASTODON_CLIENT_SECRET=${cfgSecret."postiz/mastodon/client_secret"}
            MASTODON_URL=https://mastodon.social

            # linkedin
            LINKEDIN_CLIENT_ID=${cfgSecret."postiz/linkedin/client_id"}
            LINKEDIN_CLIENT_SECRET=${cfgSecret."postiz/linkedin/client_secret"}

            # x
            X_API_KEY=${cfgSecret."postiz/x/api_key"}
            X_API_SECRET=${cfgSecret."postiz/x/api_key_secret"}

            # discord
            DISCORD_CLIENT_ID=${cfgSecret."postiz/discord/client_id"}
            DISCORD_CLIENT_SECRET=${cfgSecret."postiz/discord/client_secret"}
            DISCORD_BOT_TOKEN_ID=${cfgSecret."postiz/discord/bot_token"}

            # slack
            SLACK_ID=${cfgSecret."postiz/slack/client_id"}
            SLACK_SECRET=${cfgSecret."postiz/slack/client_secret"}
          '';
        restartUnits = [ "${subdomain}.service" ];
      };
      templates."postgres.env" = {
        mode = "0440";
        content = # sh
          ''
            POSTGRES_PASSWORD=${cfgSecret."postiz/internal/postgres_password"};
          '';
        restartUnits = [ "${subdomain}-postgres.service" ];
      };
    };

    services.local-networking.subdomains = [ subdomain ];

    virtualisation.quadlet =
      let
        inherit (config.virtualisation.quadlet) pods;
      in
      {
        networks."${subdomain}-network".networkConfig = { };

        pods."${subdomain}-pod" = {
          podConfig = {
            addHosts = [ "${fullHostName}:192.168.1.158" ];
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
              environmentFiles = [ config.sops.templates."postgres.env".path ];
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
              ];
              environmentFiles = [ config.sops.templates."postiz.env".path ];
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
              };
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
              labels = {
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
                "${subdomain}-postgres.service"
                "${subdomain}-redis.service"
                "${subdomain}-temporal.service"
                "${subdomain}-temporal-namespace-init.service"
              ];
              Requires = [
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

    # Required by redis to allow background saves under low memory.
    boot.kernel.sysctl."vm.overcommit_memory" = 1;
  };
}
