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
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      weather = pkgs.writeNuApplication {
        name = "hyprlock-weather";
        text =
          ./hyprlock-weather.nu
          |> builtins.readFile
          |>
            builtins.replaceStrings
              [ "\${sansFont}" "\${agenda}" ]
              [
                (fonts.name "sans")
                (lib.getExe (
                  pkgs.writeShellApplication {
                    name = "hyprlock-agenda";
                    runtimeInputs = [
                      pkgs.coreutils
                      pkgs.curl
                      pkgs.jq
                    ];
                    text = builtins.readFile ./hyprlock-agenda.sh;
                  }
                ))
              ];
      };
      potd = pkgs.writeShellApplication {
        name = "hyprlock-potd";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.fontconfig
          pkgs.gnugrep
          pkgs.gnused
          pkgs.imagemagick
          pkgs.jq
        ];
        text =
          builtins.readFile ./hyprlock-potd.sh
          |> builtins.replaceStrings [ "\${weather}" ] [ (lib.getExe weather) ];
      };
    in
    {
      xdg.configFile."hyprlock-weather/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink
          osConfig.sops.templates."hyprlock-weather.toml".path;

      # `hyprlock-weather 0|1 [--hilo]` renders the Today/Tomorrow card label: weather row, a gap
      # the baked graph fills, then the agenda. Same source and weatherCode→glyph mapping as the
      # notification-center Weather card, so the two stay visually consistent.
      _module.args.hyprlock-weather = weather;

      # Re-bake the lock background every 15 minutes (and soon after login): the cards follow the agenda's
      # length and the graphs the forecast; hyprlock reloads the image while locked.
      systemd.user.services.hyprlock-potd = {
        Unit.Description = "Bake the hyprlock picture-of-the-day background";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe potd;
        };
      };
      systemd.user.timers.hyprlock-potd = {
        Unit.Description = "Re-bake the hyprlock background every 15 minutes";
        Timer = {
          OnStartupSec = "1min";
          OnCalendar = "*:0/15";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
