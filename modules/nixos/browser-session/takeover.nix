{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.browser-session-takeover;
      stateDir = "/var/lib/browser-session-mcp";
      inherit (config.services.local-networking) baseDomain;
      chromeWsBase = "wss://${config.services.chrome-headless.subdomain}.${baseDomain}";
    in
    {
      options.services.browser-session-takeover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.services.chrome-headless.enable;
          description = ''
            Serve the human-takeover page: a live view of a session's active page
            that lets a human complete a login/passkey themselves, so credentials
            never pass through the agent. All CDP traffic is browser↔Chrome (via
            the chrome.<base> route); this daemon only serves the page and accepts
            the "Done" signal, communicating with the MCP through ${stateDir}/takeover.
          '';
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chrome-takeover";
          description = "Subdomain Traefik routes to the takeover daemon.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 9223;
          description = "Local port the takeover daemon binds on 127.0.0.1.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.local-networking.subdomains = [ cfg.subdomain ];

        # Host-side daemon, same shape as the listener: shares ${stateDir} with
        # the in-container MCP via the bind mount declared in the mcp-proxy
        # server module.
        systemd.services.browser-session-takeover = {
          description = "browser-session-mcp human-takeover page server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            TAKEOVER_BIND = "127.0.0.1:${toString cfg.port}";
            TAKEOVER_DIR = "${stateDir}/takeover";
            CHROME_WS_BASE = chromeWsBase;
          };

          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session-takeover";
            # Tickets/sentinels are written by the container MCP as root; match
            # so both sides can read/write the shared takeover dir.
            User = "root";
            Restart = "always";
            RestartSec = 2;
            StandardOutput = "journal";
            StandardError = "journal";
          };
        };

        systemd.tmpfiles.rules = [
          # Tickets carry a sessionId + targetId (not secrets), but the token is
          # the only guard on the live link — keep the dir root-only.
          "d ${stateDir}/takeover 0700 root root - -"
          "d ${stateDir}/takeover/tokens 0700 root root - -"
          "d ${stateDir}/takeover/done 0700 root root - -"
          "d ${stateDir}/takeover/claims 0700 root root - -"
        ];
      };
    };
}
