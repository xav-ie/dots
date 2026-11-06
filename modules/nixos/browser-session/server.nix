# The browser-session MCP server (over HTTP) and its takeover and listener
# daemons, as one container in Chrome's pod; the reaper runs in it on a host
# timer. Traefik routes mcp.<base>/servers/browser-session/ here, so Executor's
# URL is the same one the mcp-proxy container used to serve.
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
      cfg = config.services.browser-session;
      name = "browser-session";
      image = "localhost/${name}:latest";
      mcpHost = "mcp.${baseDomain}";
      mcpPort = 9224;
      exe = lib.getExe' cfg.package "browser-session";

      # Any daemon exiting takes the container down so systemd restarts all of
      # them; TERM is forwarded so the MCP server flushes its state on stop.
      entry = pkgs.writeShellApplication {
        name = "browser-session-entry";
        text = ''
          # shellcheck disable=SC2329 # invoked by the trap
          stop() {
            mapfile -t pids < <(jobs -p)
            kill -TERM "''${pids[@]}" 2>/dev/null || true
            wait
          }
          trap stop TERM INT
          ${exe} mcp &
          ${exe} takeover &
          ${exe} listener &
          wait -n
          exit 1
        '';
      };

      # Executor's browser-session app lists the tools its deployment saw, so a
      # new server release (new tools, new arguments) stays invisible until
      # the app is deployed again; reading its tools doesn't refresh them. When
      # the container (re)starts, wait for the server to answer, then redeploy
      # the app at the commit it already runs.
      executorPort = toString config.services.executor.port;
      refreshExecutorApp = pkgs.writeNuApplication {
        name = "browser-session-executor-refresh";
        text = # nu
          ''
            let api = "http://127.0.0.1:${executorPort}"
            let token = open /run/secrets/shell-env | lines | where $it starts-with "EXECUTOR_AUTH_TOKEN=" | first | str replace "EXECUTOR_AUTH_TOKEN=" ""
            let headers = {Authorization: $"Bearer ($token)"}

            # Without its token the server answers 401 once it is up; 5xx or no
            # answer means it (or traefik's route to it) isn't yet.
            def wait-for-server [url: string] {
              for _ in 1..90 {
                let status = try { http get --full --allow-errors --max-time 5sec $url | get status } catch { 0 }
                if $status > 0 and $status < 500 { return }
                sleep 2sec
              }
              error make {msg: "browser-session-executor-refresh: the server never answered"}
            }

            def list-apps [api: string, headers: record] {
              for _ in 1..90 {
                try { return (http get --max-time 10sec --headers $headers $"($api)/v1/apps") }
                sleep 2sec
              }
              error make {msg: "browser-session-executor-refresh: executor did not list its apps"}
            }

            wait-for-server "https://${mcpHost}/servers/${name}/mcp/"
            let apps = list-apps $api $headers
            let app = $apps | where slug == "${name}" | first
            let commit = http get --headers $headers $"($api)/v1/apps/($app.id)/version" | get sourceCommit
            let deployed = http post --content-type application/json --headers $headers $"($api)/v1/apps/deploy" {owner: $app.owner, app: $app.id, commit: $commit}
            print $"browser-session-executor-refresh: redeployed ($app.slug) at ($commit) as ($deployed.app.activeDeployment)"
          '';
      };

      server-image = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/${name}";
        tag = "latest";
        contents = [
          cfg.package
          entry
          pkgs.cacert
        ];
        config = {
          Cmd = [ (lib.getExe entry) ];
          Env = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
        };
      };
    in
    {
      sops = {
        secrets = {
          # The MCP port is reachable from the host and every container, so it
          # requires this bearer token, which only Executor's browser-session
          # app holds.
          "browser-session/mcp_token" = { };
          "browser-session/typesafe_api_key" = { };
        };
        # TYPESAFE_API_KEY powers `jev:` selectors (click/type/press_key): the
        # Jev decision model picks the element.
        templates."browser-session-env" = {
          content = ''
            MCP_HTTP_TOKEN=${config.sops.placeholder."browser-session/mcp_token"}
            TYPESAFE_API_KEY=${config.sops.placeholder."browser-session/typesafe_api_key"}
          '';
          mode = "0400";
          restartUnits = [ "podman-${name}.service" ];
        };
      };

      services.local-networking.subdomains = [ cfg.takeover.subdomain ];

      virtualisation.oci-containers.containers.${name} = {
        autoStart = true;
        imageFile = server-image;
        inherit image;
        environment = {
          BROWSER_URL = cfg.browserUrl;
          MAX_IDLE_HOURS = toString cfg.reaper.maxIdleHours;
          # Requests arrive through Traefik with the public Host, which the MCP
          # server rejects unless allowed.
          MCP_HTTP_ALLOWED_HOSTS = mcpHost;
          MCP_HTTP_BIND = "0.0.0.0:${toString mcpPort}";
          STATE_DIR = cfg.stateDir;
          TAKEOVER_BASE_URL = "https://${cfg.takeover.subdomain}.${baseDomain}";
          TAKEOVER_BIND = "${cfg.takeover.address}:${toString cfg.takeover.port}";
        }
        // lib.optionalAttrs cfg.reaper.closeOrphanTabs { REAP_ORPHAN_TABS = "1"; };
        environmentFiles = [ config.sops.templates."browser-session-env".path ];
        volumes = [ "${cfg.stateDir}:${cfg.stateDir}" ];
        extraOptions = [ "--pod=${cfg.pod}" ];
        labels = {
          "traefik.enable" = "true";
          "traefik.docker.network" = "podman";

          # Longer than mcp's Host-only rule, so Traefik prefers it for this path.
          "traefik.http.routers.${name}-mcp.entrypoints" = "websecure";
          "traefik.http.routers.${name}-mcp.rule" = "Host(`${mcpHost}`) && PathPrefix(`/servers/${name}/`)";
          "traefik.http.routers.${name}-mcp.tls" = "true";
          "traefik.http.routers.${name}-mcp.tls.certResolver" = "cloudflare";
          "traefik.http.routers.${name}-mcp.middlewares" = "${name}-mcp";
          "traefik.http.routers.${name}-mcp.service" = "${name}-mcp";
          "traefik.http.middlewares.${name}-mcp.replacepathregex.regex" = "^/servers/${name}/mcp/?";
          "traefik.http.middlewares.${name}-mcp.replacepathregex.replacement" = "/mcp";
          "traefik.http.services.${name}-mcp.loadbalancer.server.port" = toString mcpPort;

          "traefik.http.routers.${name}-takeover.entrypoints" = "websecure";
          "traefik.http.routers.${name}-takeover.rule" = "Host(`${cfg.takeover.subdomain}.${baseDomain}`)";
          "traefik.http.routers.${name}-takeover.tls" = "true";
          "traefik.http.routers.${name}-takeover.tls.certResolver" = "cloudflare";
          "traefik.http.routers.${name}-takeover.service" = "${name}-takeover";
          "traefik.http.services.${name}-takeover.loadbalancer.server.port" = toString cfg.takeover.port;
        };
      };

      systemd.services."podman-${name}" = {
        after = [
          "browser-session-pod.service"
          "podman-browser-session-chrome.service"
        ];
        requires = [ "browser-session-pod.service" ];
        wants = [ "podman-browser-session-chrome.service" ];
        partOf = [ "browser-session-pod.service" ];
      };

      # wantedBy starts it with the container; partOf runs it again whenever
      # the container restarts (a new release).
      systemd.services.browser-session-executor-refresh = lib.mkIf config.services.executor.enable {
        description = "Redeploy Executor's browser-session app so it lists the server's tools";
        after = [
          "podman-${name}.service"
          "executor-web.service"
        ];
        partOf = [ "podman-${name}.service" ];
        wantedBy = [ "podman-${name}.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = config.defaultUser;
          ExecStart = lib.getExe refreshExecutorApp;
        };
      };

      # Same schedule as the upstream timer, run inside the container so it
      # reaches Chrome on the pod's loopback.
      systemd.services.browser-session-reaper = {
        description = "Close idle browser-session sessions";
        after = [ "podman-${name}.service" ];
        requires = [ "podman-${name}.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe pkgs.podman} exec ${name} ${exe} reaper";
        };
      };
      systemd.timers.browser-session-reaper = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Give Chrome a chance to come up before the first sweep.
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.reaper.interval;
          Persistent = true;
        };
      };
    };
}
