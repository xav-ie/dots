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
        ExecStart = "${pkgs.pkgs-mine.executor}/bin/executor web --port ${toString cfg.port} --allowed-host ${cfg.subdomain}.${config.services.local-networking.baseDomain}";
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "executor-web";
      };
    };
  };
}
