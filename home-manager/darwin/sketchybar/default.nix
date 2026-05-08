{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  # Single source of truth for the bar height. Consumed by
  # - `sketchybarrc.nu` via `(get_bar_height)` from nix-settings.nu
  # - the sketchybar-hover daemon via the SKETCHYBAR_BAR_HEIGHT env var
  barHeight = "32";

  # so that I don't have to hard-code $HOME
  sketchybarWrapper = pkgs.writeShellScript "sketchybar-wrapper" ''
    exec ${pkgs.sketchybar}/bin/sketchybar --config "$HOME/.config/sketchybar/sketchybarrc" "$@"
  '';

  # TODO: get this to work
  # sketchybarReload = pkgs.writeShellScript "sketchybar-reload" ''
  #   # SDKROOT="$(xcrun --show-sdk-path)"
  #   swift ${./sketchybarReload.swift}
  # '';
in
{
  config = {
    home = {
      packages = [ pkgs.pkgs-bleeding.sketchybar ];
    };

    xdg.configFile = {
      "sketchybar/nix-settings.nu".text = # nu
        ''
          def get_icon_font [] {
            "${fonts.configs.sketchybar.icon-font}"
          }
          def get_label_font [] {
            "${fonts.configs.sketchybar.label-font}"
          }
          def get_bar_height [] {
            ${barHeight}
          }
        '';
      "sketchybar/sketchybarrc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/sketchybarrc.nu";
      "sketchybar/open_volume_control.scpt".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/open_volume_control.scpt";
      "sketchybar/select_control_center.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/select_control_center.nu";

      "sketchybar/plugins/battery.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/battery.nu";
      "sketchybar/plugins/battery_icon.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/battery_icon.nu";
      "sketchybar/plugins/clock.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/clock.nu";
      "sketchybar/plugins/clock_icon.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/clock_icon.nu";
      "sketchybar/plugins/control_center.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/control_center.nu";
      "sketchybar/plugins/front_app.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/front_app.nu";
      "sketchybar/plugins/space.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/space.nu";
      "sketchybar/plugins/volume.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/volume.nu";
      "sketchybar/plugins/volume_icon.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/volume_icon.nu";
      "sketchybar/plugins/wifi.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/wifi.nu";
      "sketchybar/plugins/wifi_background.nu".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/darwin/sketchybar/plugins/wifi_background.nu";
    };

    launchd.agents.sketchybar = {
      enable = true;
      config = {
        Debug = true;
        Program = builtins.toString sketchybarWrapper;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/sketchybar.log";
        StandardErrorPath = "/tmp/sketchybar.err";
        StartInterval = 5;
        EnvironmentVariables.PATH = "${
          lib.makeBinPath [
            pkgs.nushell
            pkgs.sketchybar
            pkgs.bash
            pkgs.pkgs-mine.sketchybar-hover
          ]
        }:/usr/bin";
      };
    };

    # This agent listens through pmset, removing the need for a timer.
    launchd.agents.sketchybar-battery = {
      inherit (config.launchd.agents.sketchybar) enable;
      config = {
        Debug = true;
        Program = "${pkgs.pkgs-mine.sketchybar-battery}/bin/sketchybar-battery";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/sketchybar-battery.log";
        StandardErrorPath = "/tmp/sketchybar-battery.err";
      };
    };

    # Owns per-item hover state. Items invoke `sketchybar-hover` (the tiny
    # client) on mouse events; this daemon receives those over a Unix socket
    # and pushes batched `--set` updates back to sketchybar. Avoids the
    # per-hover nushell fork-storm and self-heals dropped mouse.exited events.
    launchd.agents.sketchybar-hover = {
      inherit (config.launchd.agents.sketchybar) enable;
      config = {
        Debug = true;
        Program = "${pkgs.pkgs-mine.sketchybar-hover}/bin/sketchybar-hoverd";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/sketchybar-hover.log";
        StandardErrorPath = "/tmp/sketchybar-hover.err";
        EnvironmentVariables = {
          PATH = "${lib.makeBinPath [ pkgs.sketchybar ]}:/usr/bin";
          # Set to "1" to log every event/state/sketchybar invocation to
          # /tmp/sketchybar-hover.err. Off by default to keep the log file
          # small in normal use.
          SKETCHYBAR_HOVER_DEBUG = "0";
          # Bar height used by the daemon's polling fallback to detect
          # "cursor left the bar". Sourced from the same `barHeight` used by
          # nix-settings.nu so all three places (Nix, Nu, Rust) stay in sync.
          SKETCHYBAR_BAR_HEIGHT = barHeight;
          # Stack traces in /tmp/sketchybar-hover.err when the daemon's
          # panic hook fires. No overhead during normal operation since
          # panics are the abort path.
          RUST_BACKTRACE = "1";
        };
      };
    };

    # # reload sketchybar on screen off/on
    # # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2560079227
    # launchd.agents.sketchybarReload = {
    #   enable = true;
    #   config = {
    #     Debug = true;
    #     Program = "${sketchybarReload}";
    #     KeepAlive = true;
    #     RunAtLoad = true;
    #     StandardOutPath = "/tmp/sketchybarReload.log";
    #     StandardErrorPath = "/tmp/sketchybarReload.err";
    #   };
    # };
  };
}
