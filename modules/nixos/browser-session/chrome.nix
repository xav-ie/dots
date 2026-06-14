{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.chrome-headless;
    in
    {
      options.services.chrome-headless = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run a persistent headless Chrome exposing the DevTools Protocol.";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chrome";
          description = "Subdomain for the DevTools HTTP/WS endpoint (under services.local-networking.baseDomain).";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 9222;
          description = "Local DevTools port bound to 127.0.0.1.";
        };
        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/chrome";
          description = "Chrome user-data-dir. Persists cookies/storage across Chrome restarts.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.local-networking.subdomains = [ cfg.subdomain ];

        users.users.chrome-headless = {
          isSystemUser = true;
          group = "chrome-headless";
          home = cfg.dataDir;
          createHome = false;
        };
        users.groups.chrome-headless = { };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 chrome-headless chrome-headless - -"
        ];

        # Chrome binds DevTools to 127.0.0.1 only — Chrome rejects non-loopback
        # Host headers as DNS-rebinding protection. Traefik (see nginx.nix) rewrites
        # the public Host header to `localhost` before forwarding here.
        systemd.services.chrome-headless = {
          description = "Persistent headless Chrome for automation";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            User = "chrome-headless";
            Group = "chrome-headless";
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";
            RestartSec = 5;
            ExecStart =
              [
                "${pkgs.pkgs-mine.chrome-headless-shell}/bin/chrome-headless-shell"
                "--no-sandbox"
                "--disable-gpu"
                "--disable-dev-shm-usage"
                "--user-data-dir=${cfg.dataDir}"
                "--remote-debugging-address=127.0.0.1"
                "--remote-debugging-port=${cfg.port |> toString}"
                # Pass Chrome's Origin check for WebSocket upgrades from Traefik.
                "--remote-allow-origins=*"
              ]
              |> lib.concatStringsSep " ";
          };
        };
      };
    };
}
