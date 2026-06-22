# cursortab → Mercury usage observability (metrics + logs, 100% local).
#
#   cursortab daemon ─OTLP/https─▶ traefik ─▶ Prometheus (metrics) ─┐
#                    └─OTLP/https─▶ traefik ─▶ Loki (logs) ──────────┴─▶ Grafana
#                                                       traefik ◀─ browser ─▶ Grafana
#
# All three run as containers in a single podman pod (quadlet), sharing one
# network namespace so they reach each other over localhost. NOTHING binds a
# host port: traefik (docker provider) is the only ingress, routing each
# container by the labels below — Grafana at grafana.lalala.casa, and the two
# OTLP ingest endpoints at prometheus./loki.lalala.casa. The cursortab daemon is
# a host process (a child of nvim); it pushes over HTTPS to those hostnames,
# which resolve to 127.0.0.1 locally (traefik.nix's extraHosts) and only on this
# box. The daemon is a local, unpushed fork of cursortab.nvim (branch
# usage-logging) whose telemetry is a no-op unless an OTLP endpoint is in its
# environment — so this module both stands up the backends and exports the env
# that switches them on.
#
# Dashboards (./dashboards) and their LogQL/PromQL are the source of truth for
# queries; don't duplicate them here.
{
  flake.modules.nixos.praesidium =
    {
      inputs,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.cursortab-observability;
      inherit (config.services.local-networking) baseDomain;

      # One subdomain per container. grafana = UI; prometheus/loki = the OTLP
      # ingest endpoints the host daemon pushes to.
      grafanaHost = "grafana.${baseDomain}";
      prometheusHost = "prometheus.${baseDomain}";
      lokiHost = "loki.${baseDomain}";

      # traefik docker-provider labels for a container in the pod. Each gets its
      # own router + service; all resolve to the shared pod IP on `port`.
      mkTraefikLabels = name: host: port: {
        "traefik.enable" = "true";
        "traefik.http.routers.${name}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${name}-secure.rule" = "Host(`${host}`)";
        "traefik.http.routers.${name}-secure.tls" = "true";
        "traefik.http.routers.${name}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${name}-secure.service" = "${name}-svc";
        "traefik.http.services.${name}-svc.loadbalancer.server.port" = toString port;
      };

      dataDir = "/var/lib/cursortab-observability";

      # In-pod ports. Containers share the pod's network namespace, so these
      # only need to not collide with each other.
      promInternalPort = 9090;
      lokiInternalPort = 3100;
      grafanaInternalPort = 3000;

      # Image default UIDs the data dirs must be owned by (containers run
      # rootful, as their image user). Verify with `podman run --rm IMAGE id`:
      #   prom/prometheus → nobody (65534); grafana/loki → 10001; grafana → 472.
      promUID = "65534";
      lokiUID = "10001";
      grafanaUID = "472";

      yaml = pkgs.formats.yaml { };

      prometheusConfig = yaml.generate "prometheus.yml" {
        global = { };
        scrape_configs = [
          {
            job_name = "prometheus";
            static_configs = [ { targets = [ "localhost:${toString promInternalPort}" ]; } ];
          }
        ];
      };

      # Single-binary, filesystem-backed. allow_structured_metadata is what
      # makes the OTLP log attributes (file, session id, tokens, response id)
      # queryable; the daemon pushes to the built-in /otlp/v1/logs endpoint.
      lokiConfig = yaml.generate "loki.yaml" {
        auth_enabled = false;
        server = {
          http_listen_address = "0.0.0.0";
          http_listen_port = lokiInternalPort;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 0; # ephemeral; internal single-binary use only
          log_level = "warn";
        };
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/loki";
          storage.filesystem = {
            chunks_directory = "/loki/chunks";
            rules_directory = "/loki/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config = {
          allow_structured_metadata = true;
          volume_enabled = true;
          retention_period = "0s"; # keep everything (low volume, single user)
        };
        analytics.reporting_enabled = false;
      };

      # Grafana provisioning. Persisted datasources are deleted-by-name first so
      # the fixed-uid (re)create stays idempotent across uid changes (otherwise
      # it fails with "data source not found"). UIDs are referenced by the
      # dashboards.
      grafanaDatasources = yaml.generate "datasources.yaml" {
        apiVersion = 1;
        deleteDatasources = [
          {
            name = "Prometheus";
            orgId = 1;
          }
        ];
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            uid = "cursortab-prometheus";
            access = "proxy";
            url = "http://localhost:${toString promInternalPort}";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            uid = "cursortab-loki";
            access = "proxy";
            url = "http://localhost:${toString lokiInternalPort}";
          }
        ];
      };

      # Read-only in the UI; edit the JSON and rebuild.
      grafanaDashboardsProvider = yaml.generate "dashboards.yaml" {
        apiVersion = 1;
        providers = [
          {
            name = "cursortab";
            options.path = "/etc/grafana/dashboards";
            disableDeletion = true;
            allowUiUpdates = false;
          }
        ];
      };
    in
    {
      imports = [
        inputs.quadlet-nix.nixosModules.quadlet
      ];

      options.services.cursortab-observability = {
        enable = lib.mkEnableOption "local Prometheus + Loki + Grafana (podman pod) for cursortab/Mercury usage";

        retention = lib.mkOption {
          type = lib.types.str;
          default = "90d";
          description = "Prometheus TSDB retention window.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.local-networking.subdomains = [
          "grafana"
          "loki"
          "prometheus"
        ];

        virtualisation.quadlet =
          let
            inherit (config.virtualisation.quadlet) networks pods;
          in
          {
            networks.cursortab-observability.networkConfig = { };

            # No publishPorts — traefik is the only ingress (see the labels on
            # each container).
            pods.cursortab-observability.podConfig.networks = [ networks.cursortab-observability.ref ];

            containers = {
              cursortab-prometheus = {
                containerConfig = {
                  image = "docker.io/prom/prometheus:latest";
                  pod = pods.cursortab-observability.ref;
                  volumes = [
                    "${prometheusConfig}:/etc/prometheus/prometheus.yml:ro"
                    "${dataDir}/prometheus:/prometheus"
                  ];
                  # Replaces the image's default CMD, so the full flag set is
                  # required. --web.enable-otlp-receiver turns on native OTLP
                  # ingest at /api/v1/otlp/v1/metrics. otlp-deltatocumulative
                  # accumulates the daemon's delta-temporality counters into one
                  # stable cumulative series that survives its per-session
                  # restarts (the daemon exports deltas precisely because it is
                  # short-lived); without it the delta samples are rejected.
                  exec = [
                    "--config.file=/etc/prometheus/prometheus.yml"
                    "--enable-feature=otlp-deltatocumulative"
                    "--storage.tsdb.path=/prometheus"
                    "--storage.tsdb.retention.time=${cfg.retention}"
                    "--web.enable-otlp-receiver"
                  ];
                  # OTLP metrics ingest at /api/v1/otlp/v1/metrics.
                  labels = mkTraefikLabels "prometheus" prometheusHost promInternalPort;
                };
                serviceConfig.Restart = "always";
              };

              cursortab-loki = {
                containerConfig = {
                  image = "docker.io/grafana/loki:latest";
                  pod = pods.cursortab-observability.ref;
                  volumes = [
                    "${lokiConfig}:/etc/loki/loki.yaml:ro"
                    "${dataDir}/loki:/loki"
                  ];
                  exec = [ "-config.file=/etc/loki/loki.yaml" ];
                  # OTLP logs ingest at /otlp/v1/logs.
                  labels = mkTraefikLabels "loki" lokiHost lokiInternalPort;
                };
                serviceConfig.Restart = "always";
              };

              cursortab-grafana = {
                containerConfig = {
                  image = "docker.io/grafana/grafana:latest";
                  pod = pods.cursortab-observability.ref;
                  volumes = [
                    "${grafanaDatasources}:/etc/grafana/provisioning/datasources/cursortab.yaml:ro"
                    "${grafanaDashboardsProvider}:/etc/grafana/provisioning/dashboards/cursortab.yaml:ro"
                    "${./dashboards}:/etc/grafana/dashboards:ro"
                    "${dataDir}/grafana:/var/lib/grafana"
                  ];
                  environments = {
                    GF_SERVER_HTTP_PORT = toString grafanaInternalPort;
                    GF_SERVER_ROOT_URL = "https://${grafanaHost}";
                    # Reachable only through traefik on this single-user box, so
                    # skip auth entirely. Revert (login form + admin secret) if
                    # this is ever exposed to a wider network.
                    GF_AUTH_ANONYMOUS_ENABLED = "true";
                    GF_AUTH_ANONYMOUS_ORG_ROLE = "Admin";
                    GF_AUTH_DISABLE_LOGIN_FORM = "true";
                  };
                  labels = mkTraefikLabels "grafana" grafanaHost grafanaInternalPort;
                };
                serviceConfig.Restart = "always";
                unitConfig.After = [
                  "cursortab-loki.service"
                  "cursortab-prometheus.service"
                ];
              };
            };
          };

        systemd.tmpfiles.rules = [
          "d ${dataDir} 0755 root root -"
          "d ${dataDir}/grafana 0755 ${grafanaUID} ${grafanaUID} -"
          "d ${dataDir}/loki 0755 ${lokiUID} ${lokiUID} -"
          "d ${dataDir}/prometheus 0755 ${promUID} ${promUID} -"
        ];

        # The daemon inherits nvim's environment (daemon.lua spawns it with
        # env = vim.fn.environ()). Metrics and logs go to different services, so
        # use the PER-SIGNAL endpoints — the SDK treats these as the FULL path
        # (it appends nothing), so include /v1/metrics and /otlp/v1/logs here.
        # These hostnames resolve to 127.0.0.1 on this box (traefik.nix
        # extraHosts) and carry a real (Let's Encrypt via Cloudflare DNS) cert,
        # so the push is plain HTTPS with no extra trust wiring.
        environment.sessionVariables = {
          OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
          OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "https://${prometheusHost}/api/v1/otlp/v1/metrics";
          OTEL_EXPORTER_OTLP_LOGS_ENDPOINT = "https://${lokiHost}/otlp/v1/logs";
          OTEL_SERVICE_NAME = "cursortab";
        };

        # Query notes (verified against live data):
        #   - Prometheus: dots→underscores, counters +_total, histograms
        #     +_sum/_count/_bucket.
        #   - Loki: OTLP attributes are structured metadata — filter with a
        #     pipeline stage (`| event="completion.request"`), NOT in the stream
        #     selector `{}`, and with no `| json`. Names lowercase dots to
        #     underscores (cursortab_file, gen_ai_usage_input_tokens, …).
      };
    };
}
