{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    {
      config = {
        # enable wires up the udev rules (services.udev.packages) + i2c kernel
        # modules so `openrgb -p` can reach devices as the logged-in user via
        # uaccess ACLs. Profiles already live in ~/.config/OpenRGB, so the
        # start-work/kill-spyware scripts run fully standalone.
        services.hardware.openrgb = {
          enable = true;
          package = pkgs.pkgs-mine.openrgb-appimage;
        };

        # ...but don't run the persistent --server daemon: it only existed to
        # broker hardware access, which the udev rules now grant directly.
        systemd.services.openrgb.enable = false;
      };
    };
}
