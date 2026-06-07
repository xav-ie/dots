{
  flake.modules.nixos.praesidium =
    {
      config,
      pkgs,
      ...
    }:
    let
      tokenFile = config.sops.secrets."cloudflare/tunnels/praesidium".path;
    in
    {
      config = {
        users.users.cloudflared = {
          isSystemUser = true;
          group = "cloudflared";
          home = "/var/lib/cloudflared";
          createHome = true;
        };
        users.groups.cloudflared = { };

        sops.secrets."cloudflare/tunnels/praesidium" = {
          owner = "cloudflared";
          group = "cloudflared";
          restartUnits = [ "cloudflared-tunnel-praesidium.service" ];
        };

        systemd.services.cloudflared-tunnel-praesidium = {
          description = "Cloudflare Tunnel for praesidium";
          # cloudflared queries the system resolver at startup; gate on
          # dns-online.target (defined in dns-online.nix) so the lookup hits
          # a *responsive* resolver rather than racing the socket bind.
          after = [
            "network-online.target"
            "dns-online.target"
          ];
          wants = [
            "network-online.target"
            "dns-online.target"
          ];
          wantedBy = [ "multi-user.target" ];

          script = ''
            ${pkgs.cloudflared}/bin/cloudflared tunnel run --token "$(cat ${tokenFile})"
          '';

          serviceConfig = {
            Type = "simple";
            User = "cloudflared";
            Group = "cloudflared";
            Restart = "always";
            RestartSec = "5s";
            # Hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            MemoryDenyWriteExecute = true;
            LockPersonality = true;
            RestrictRealtime = true;
          };
        };
      };
    };
}
