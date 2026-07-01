{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.muscat;
    in
    {
      options.services.muscat = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8763;
          description = "Loopback port the static server listens on.";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "muscat";
          description = "Subdomain under the base domain Traefik routes to this tool.";
        };
      };

      config = {
        services.local-networking.subdomains = [ cfg.subdomain ];

        # Serve the single, self-contained board.html built by packages/muscat.
        # `--index board.html` makes it the response for `/`.
        systemd.services.muscat = {
          description = "Static server for the Muscat board poster";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe pkgs.miniserve)
              "--interfaces"
              "127.0.0.1"
              "--port"
              (toString cfg.port)
              "--index"
              "board.html"
              "${pkgs.pkgs-mine.muscat}"
            ];
            Restart = "on-failure";
            DynamicUser = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
          };
        };
      };
    };
}
