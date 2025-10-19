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
  };
}
