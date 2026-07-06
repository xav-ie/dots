{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config) defaultUser;
      cfg = config.services.executor;
      userHome = "/home/${defaultUser}";
      executorWorkspace = "/var/lib/executor-web";

      # Boot readiness gate. `after = podman-mcp.service` only waits for the
      # container to launch — mcp-proxy still needs a few seconds to set up its
      # servers and be routed by traefik. executor's config-sync probes each
      # source once and gives up on failure, so without this a boot leaves every
      # source with an empty tool manifest until a manual `restart executor-web`.
      # Poll mcp-proxy's server-agnostic `/status` endpoint (200 once its HTTP
      # server is up and traefik routes it) rather than any named server. Exit 0
      # on timeout so executor still starts instead of hanging the boot.
      waitForMcpProxy = pkgs.writeShellScript "executor-wait-mcp-proxy" ''
        url="https://mcp.${config.services.local-networking.baseDomain}/status"
        for i in $(seq 1 90); do
          code=$(${pkgs.curl}/bin/curl -sk -m 3 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)
          [ "$code" = "200" ] && { echo "mcp-proxy ready after $(( (i - 1) * 2 ))s"; exit 0; }
          sleep 2
        done
        echo "mcp-proxy not ready after 180s; starting executor anyway" >&2
        exit 0
      '';
    in
    {
      options.services.executor = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable the Executor web service";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "executor";
          description = "The subdomain for Executor";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 38972;
          description = "Port for the Executor web server (opencode port + 1)";
        };
      };

      config = lib.mkIf cfg.enable {
        # Register subdomain
        services.local-networking.subdomains = [ cfg.subdomain ];

        # Create workspace directory
        systemd.tmpfiles.rules = [
          "d ${executorWorkspace} 0755 ${defaultUser} users - -"
        ];

        # Main executor web service
        systemd.services.executor-web = {
          description = "Executor web server";
          after = [
            "network.target"
            "podman-mcp.service"
          ];
          wantedBy = [ "multi-user.target" ];
          # Intentionally no `partOf`/`bindsTo` on podman-mcp: with stateless
          # streamable HTTP, proxy restarts are transparent. Cascading a restart
          # here would re-run config-sync before the new proxy is listening,
          # leaving sources with empty tool manifests until a manual re-probe.

          environment = {
            HOME = userHome;
          };

          serviceConfig = {
            User = defaultUser;
            WorkingDirectory = executorWorkspace;
            # Gate config-sync on the proxy being reachable (see waitForMcpProxy).
            ExecStartPre = waitForMcpProxy;
            ExecStart = "${pkgs.pkgs-mine.executor}/bin/executor web --port ${cfg.port |> toString} --allowed-host ${cfg.subdomain}.${config.services.local-networking.baseDomain}";
            Restart = "on-failure";
            RestartSec = 5;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "executor-web";
          };
        };
      };
    };
}
