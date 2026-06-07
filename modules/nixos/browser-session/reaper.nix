{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.browser-session-reaper;
      stateDir = "/var/lib/browser-session-mcp";
    in
    {
      options.services.browser-session-reaper = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.services.chrome-headless.enable;
          description = "Periodically close idle browser-session-mcp BrowserContexts.";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "30min";
          description = "How often to run the reaper (systemd OnUnitActiveSec).";
        };
        maxIdleHours = lib.mkOption {
          type = lib.types.ints.positive;
          default = 2;
          description = "Sessions idle longer than this many hours are closed.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.browser-session-reaper = {
          description = "Close idle browser-session-mcp sessions";
          after = [ "chrome-headless.service" ];
          requires = [ "chrome-headless.service" ];

          environment = {
            STATE_FILE = "${stateDir}/state.json";
            BROWSER_URL = "http://127.0.0.1:${toString config.services.chrome-headless.port}";
            MAX_IDLE_HOURS = toString cfg.maxIdleHours;
          };

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session-reaper";
            # state.json is written by the mcp-proxy container as root, and we
            # need read+write here to prune entries — match that.
            User = "root";
            StandardOutput = "journal";
            StandardError = "journal";
          };
        };

        systemd.timers.browser-session-reaper = {
          description = "Periodic reaper for browser-session-mcp";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # Don't run the moment the box boots — give Chrome a chance to come up.
            OnBootSec = "5min";
            OnUnitActiveSec = cfg.interval;
            # Catch up if we missed a run while powered off.
            Persistent = true;
          };
        };
      };
    };
}
