# Two-day forecast for hyprland.nix's WEATHER label, as a `hyprlock-weather`
# module arg. Reads $XDG_CONFIG_HOME/hyprlock-weather/config.toml like any other
# app; missing/empty → wttr.in geolocates by IP.
#
# Here that file is a symlink to a sops-rendered one, because both the repo and
# the Nix store are world-readable and the query names where I live:
#   weather:
#     location: <a wttr.in query, e.g. "~Brighton,MA">
{
  flake.modules.nixos.linux =
    { config, ... }:
    {
      sops = {
        secrets."weather/location" = {
          owner = config.defaultUser;
          mode = "0400";
        };
        templates."hyprlock-weather.toml" = {
          owner = config.defaultUser;
          mode = "0400";
          content = ''
            location = "${config.sops.placeholder."weather/location"}"
          '';
        };
      };
    };

  flake.modules.homeManager.linux =
    {
      config,
      fonts,
      osConfig,
      pkgs,
      ...
    }:
    {
      xdg.configFile."hyprlock-weather/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink
          osConfig.sops.templates."hyprlock-weather.toml".path;

      # Each day is a header plus a "rain% icon hi/lo desc" row. Same source and
      # weatherCode→glyph mapping as the notification-center Weather card, so
      # the two stay visually consistent.
      _module.args.hyprlock-weather = pkgs.writeNuApplication {
        name = "hyprlock-weather";
        text =
          ./hyprlock-weather.nu
          |> builtins.readFile
          |> builtins.replaceStrings [ "\${sansFont}" ] [ (fonts.name "sans") ];
      };
    };
}
