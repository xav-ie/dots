# originally adapted from:
# https://github.com/segator/config/blob/dd34171470fea833fd9a3db44ba99e11d8f94ea3/nixos/host/vps1/tailscale.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    environment.systemPackages = [ pkgs.tailscale ];

    services.tailscale.enable = true;

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    sops.secrets."tailscale/token" = {
      restartUnits = lib.optionals (lib.hasAttr "tailscale-autoconnect" config.systemd.services) [
        "tailscale-autoconnect.service"
      ];
    };

    systemd.services.tailscale-autoconnect = {
      description = "Automatic connection to Tailscale";

      # make sure tailscale is running before trying to connect to tailscale
      after = [
        "network-pre.target"
        "tailscale.service"
      ];
      wants = [
        "network-pre.target"
        "tailscale.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig.Type = "oneshot";

      script = lib.getExe (
        pkgs.writeNuApplication {
          name = "tailscale-login";
          runtimeInputs = with pkgs; [
            tailscale
          ];
          text =
            # nu
            ''
              # wait for tailscaled to settle
              sleep 2sec

              let status = (tailscale status -json | from json | get BackendState)
              if ($status == "NeedsLogin") {
                tailscale up -authkey (open ${config.sops.secrets."tailscale/token".path})
              }
            '';
        }
      );
    };
  };
}
