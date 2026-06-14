{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.ream;
    in
    {
      options.services.ream = {
        port = lib.mkOption {
          type = lib.types.port;
          # Uncommon port: 8086 (the binary's default) collides with common dev
          # tools, and socket activation means nothing else needs to know it.
          default = 8762;
          description = "Loopback port the socket-activated server listens on.";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "pdf";
          description = "Subdomain under the base domain Traefik routes to this tool.";
        };
      };

      config = {
        services.local-networking.subdomains = [ cfg.subdomain ];

        # systemd holds the socket; nothing runs until a connection arrives.
        systemd.sockets.ream = {
          wantedBy = [ "sockets.target" ];
          socketConfig.ListenStream = "127.0.0.1:${cfg.port |> toString}";
        };

        # No wantedBy: started on demand by ream.socket, self-exits when idle.
        systemd.services.ream = {
          description = "On-demand PDF utility server";
          requires = [ "ream.socket" ];
          after = [ "ream.socket" ];
          serviceConfig = {
            ExecStart = lib.getExe pkgs.pkgs-mine.ream;
            Restart = "no";
            DynamicUser = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
          };
        };
      };
    };
}
