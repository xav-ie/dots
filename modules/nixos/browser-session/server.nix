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
        secrets."browser-session/typesafe_api_key" = { };
        # Powers `jev:` selectors (click/type/press_key): the Jev decision
        # model picks the element.
        templates."browser-session-env" = {
          content = "TYPESAFE_API_KEY=${config.sops.placeholder."browser-session/typesafe_api_key"}";
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
