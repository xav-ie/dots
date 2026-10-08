{
  flake.modules.homeManager.linux =
    {
      config,
      pkgs,
      fonts,
      ...
    }:
    let
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
          # adw-gtk3 ships a gtk-4.0 variant, so GTK4 apps share the GTK3 theme.
          gtk4.theme = cfg.theme;
          # Note: gtk-application-prefer-dark-theme is deprecated for libadwaita apps.
          # Dark mode is controlled via dconf: org.gnome.desktop.interface.color-scheme
          # See: home-manager/programs/dconf/default.nix
        };
      };
    };
}
