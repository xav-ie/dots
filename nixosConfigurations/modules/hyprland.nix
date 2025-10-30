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

    # XDG portal configuration for hyprland
    (lib.mkIf hyprlandEnabled {
      # TIP: run `nix run nixpkgs#door-knocker` and check that portal
      # implementation has expected support
      xdg.portal =
        let
          inherit (inputs.hyprland.packages.${pkgs.system}) xdg-desktop-portal-hyprland;
        in
        {
          enable = true;
          extraPortals = [
            xdg-desktop-portal-hyprland
            pkgs.xdg-desktop-portal-gnome
          ];
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
          # NOTE: configPackages is NOT set here because Hyprland's built-in
          # config overrides our explicit config above. Hyprland's config says
          # "default=hyprland;gtk" which doesn't properly route the Settings
          # interface to GNOME portal. By omitting configPackages, NixOS uses
          # our config which properly routes Settings to gnome.
          # See: GHOSTTY_DARK_MODE_RESEARCH.md
        };
    })
  ];
}
