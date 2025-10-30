{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit ((import ../../lib/fonts.nix { inherit lib pkgs; })) fonts;
  cfg = config.gtk;
in
{
  config = {
    home.packages = [
      cfg.iconTheme.package
      cfg.theme.package
    ];
    gtk = {
      enable = true;
      font = fonts.configs.gtk;
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      # Note: gtk-application-prefer-dark-theme is deprecated for libadwaita apps.
      # Dark mode is controlled via dconf: org.gnome.desktop.interface.color-scheme
      # See: home-manager/programs/dconf/default.nix
    };
  };
}
