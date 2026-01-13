{ config, ... }:
let
  subdomain = "jellyfin";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    services.jellyfin = {
      enable = true;
      openFirewall = true;
      hardwareAcceleration = {
        enable = true;
        type = "nvenc";
        device = "/dev/nvidia0";
      };
    };

    # Grant jellyfin user access to render devices
    users.users.jellyfin.extraGroups = [
      "render"
      "video"
    ];

    # Create world-readable media directory
    systemd.tmpfiles.rules = [
      "d /media/videos 0755 ${config.defaultUser} users -"
    ];
  };
}
