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
      partOf = [ "podman-mcp.service" ];

      environment = {
        HOME = userHome;
      };

      serviceConfig = {
        User = defaultUser;
        WorkingDirectory = executorWorkspace;
        ExecStart = "${pkgs.pkgs-mine.executor}/bin/executor web --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "executor-web";
      };
    };
  };
}
