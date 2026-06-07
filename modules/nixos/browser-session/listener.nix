{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.browser-session-listener;
      stateDir = "/var/lib/browser-session-mcp";
    in
    {
      options.services.browser-session-listener = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.services.chrome-headless.enable;
          description = ''
            Run a long-lived daemon that subscribes to Chrome's CDP and writes
            every console + network event to per-session NDJSON files. Decouples
            event capture from the executor↔mcp-proxy↔subprocess chain so logs
            survive subprocess churn.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.browser-session-listener = {
          description = "browser-session-mcp event listener";
          after = [ "chrome-headless.service" ];
          requires = [ "chrome-headless.service" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            BROWSER_URL = "http://127.0.0.1:${toString config.services.chrome-headless.port}";
            LOGS_DIR = "${stateDir}/logs";
          };

          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session-listener";
            # Logs are read by the in-container MCP via a bind mount; container
            # runs as root, so writing as root keeps perms simple.
            User = "root";
            # The listener re-establishes the CDP subscription internally on
            # disconnect, but if it crashes outright we want systemd to bring it
            # back fast — restart loss window is the only event-loss vector left.
            Restart = "always";
            RestartSec = 2;
            StandardOutput = "journal";
            StandardError = "journal";
          };
        };
      };
    };
}
