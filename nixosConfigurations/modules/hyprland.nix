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
    # `programs.hyprland.enable = true` above. We only layer on the gnome
    # portal here for keyring/secret/file-chooser support.
    (lib.mkIf hyprlandEnabled {
      # TIP: run `nix run nixpkgs#door-knocker` and check that portal
      # implementation has expected support
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
        configPackages = [ pkgs.xdg-desktop-portal-gnome ];
        config =
          let
            common = {
              default = [
                "hyprland"
                "gnome"
              ];
              # TODO: what kinds of other useful settings can I set?
              # "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
            };
          in
          {
            inherit common;
            hyprland = common;
          };
      };
    })
  ];
}
