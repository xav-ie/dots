{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  cfg = config.programs.waybar;
  hyprCfg = config.programs.hyprland;
  bars = builtins.attrValues cfg.settings;
  # go through each bar and get all module names
  waybar-modules = lib.lists.flatten (
    builtins.map (
      barConfig:
      (barConfig.modules-left or [ ])
      ++ (barConfig.modules-center or [ ])
      ++ (barConfig.modules-right or [ ])
    ) bars
  );
in
{
  imports = [
    inputs.virtual-headset.homeManagerModules.default
  ];
  options.programs.waybar = {
    barHeight = lib.mkOption {
      # Statically determining the bar height is difficult. So far, the only factor of height
      # we know is padding. To get the realized height:
      # > hyprctl layers -j | jq '.. | objects | select(.namespace? == "waybar") | .h'
      # INFO: you can check the height meets the min requirement by simply running waybar
      # it will tell you if the height set is not enough
      default = 30 + hyprCfg.borderSizeNumeric * 2 + 1; # idk why plus 1
      type = lib.types.ints.positive;
    };
  };
  config = {
    home.packages =
      # audio visualizer
      lib.optional (builtins.elem "cava" waybar-modules) pkgs.cava;

    programs.virtual-headset-waybar.enable = true;

    xdg.configFile."waybar/style-dynamic.css".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/linux/waybar/style-dynamic.css";

    programs.waybar = {
      # https://github.com/elythh/nixdots/blob/58db47f160c219c3e2a9630651dfd9aab0408b1a/modules/home/opt/wayland/services/swaync/default.nix
      enable = true;
      systemd.enable = true;
      package =
        let
          libcava-src = pkgs.fetchFromGitHub {
            owner = "LukashonakV";
            repo = "cava";
            # Match libcava.wrap: v0.10.7-beta
            rev = "v0.10.7-beta";
            hash = "sha256-IX1B375gTwVDRjpRfwKGuzTAZOV2pgDWzUd4bW2cTDU=";
          };
        in
        inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
          # Fix upstream bug: postUnpack copies to subprojects/cava but libcava.wrap expects cava-0.10.7-beta
          prePatch = (old.prePatch or "") + ''
            cp -R --no-preserve=mode,ownership ${libcava-src} subprojects/cava-0.10.7-beta
          '';
          # Fix cava module regression from PR #4682: cava_frontend.hpp only supports OUTPUT_RAW
          # but cava_backend.cpp restores the original output method (OUTPUT_NONCURSES by default)
          postPatch = (old.postPatch or "") + ''
            substituteInPlace src/modules/cava/cava_backend.cpp \
              --replace-fail 'prm_.output = output;' '// prm_.output = output; // Keep OUTPUT_RAW for waybar'
          '';
        });
      settings = {
        mainBar = import ./config.nix {
          inherit
            config
            lib
            pkgs
            ;
        };
      };
      style = # css
        ''
          /* GENERAL SETTINGS */
          * {
            border: none;
            font-family: "${fonts.configs.waybar.font-family}";
            font-size: ${toString fonts.configs.waybar.font-size}px;
            box-shadow: none;
          }

          /* MODULE STYLES */
          #backlight,
          #battery,
          #bluetooth,
          #custom-bluetooth,
          #cava,
          #clock,
          #custom-arch,
          #custom-notification,
          #custom-pomodoro,
          #custom-virtual-headset,
          #custom-network,
          #pulseaudio,
          #tray,
          #workspaces {
            background: rgba(19, 6, 10, 0.65);
            border: ${toString hyprCfg.borderSizeNumeric}px solid #631f33;
            color: white;
            border-radius: 8px;
            padding: 3px 8px;
            margin-right: 8px;
            box-shadow: none;
          }

          @import url("style-dynamic.css");
        '';
    };
  };
}
