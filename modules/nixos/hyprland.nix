{
  flake.modules.nixos.linux =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      hmConfig = config.home-manager.users.${config.defaultUser};
      hyprlandEnabled = hmConfig.wayland.windowManager.hyprland.enable or false;
      hyprlockEnabled = hmConfig.programs.hyprlock.enable or false;
    in
    {
      config = lib.mkMerge [
        # PAM configuration for hyprlock
        (lib.mkIf hyprlockEnabled {
          security.pam.services.hyprlock = { };
        })

        # Enable Hyprland system-wide so its session entry, portal, and PAM
        # integration are available regardless of how we log in.
        (lib.mkIf hyprlandEnabled {
          programs.hyprland = {
            enable = true;
            package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          };
        })

        # XDG portal configuration for hyprland.
        # NOTE: the hyprland portal package and its config are added by
        # `programs.hyprland.enable = true` above. We layer on the gtk portal
        # for the FileChooser (gnome's backend only exposes Settings off a GNOME
        # session, so it cannot serve the file picker here) and gnome for the
        # remaining settings/secret interfaces.
        (lib.mkIf hyprlandEnabled {
          # TIP: run `nix run nixpkgs#door-knocker` and check that portal
          # implementation has expected support
          xdg.portal = {
            enable = true;
            extraPortals = [
              pkgs.xdg-desktop-portal-gnome
              pkgs.xdg-desktop-portal-gtk
            ];
            configPackages = [ pkgs.xdg-desktop-portal-gnome ];
            config =
              let
                common = {
                  default = [
                    "hyprland"
                    "gnome"
                  ];
                  # The gnome backend refuses FileChooser outside a GNOME session,
                  # so the gtk portal owns the file picker for Firefox/Chromium.
                  "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
                };
              in
              {
                inherit common;
                hyprland = common;
              };
          };
        })
      ];
    };
}
