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

    programs.waybar = {
      # https://github.com/elythh/nixdots/blob/58db47f160c219c3e2a9630651dfd9aab0408b1a/modules/home/opt/wayland/services/swaync/default.nix
      enable = true;
      systemd.enable = true;
      package = inputs.waybar.packages.${pkgs.system}.default;
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

          window#waybar {
            background: transparent;
          }

          /*this is the general box holding all modules*/
          window#waybar > box {
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
          #network,
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

          /*shift down these modules, fixes awkward text too close to top*/
          #clock,
          #custom-pomodoro,
          #custom-virtual-headset,
          #network,
          #bluetooth,
          #custom-bluetooth,
          #pulseaudio,
          #cava,
          #workspaces,
          #custom-arch {
            padding-top: 4px;
            padding-bottom: 2px;
          }

          /* left joined */
          #backlight,
          #bluetooth,
          #custom-bluetooth,
          #cava {
            border-top-right-radius: 0;
            border-bottom-right-radius: 0;
            padding-right: 3px;
            margin-right: 0;
            border-right: none;
          }

          /* middle joined */
          #pulseaudio {
            border-radius: 0;
            padding-left: 3px;
            padding-right: 3px;
            margin-right: 0;
            border-left: none;
            border-right: none;
          }

          /* right joined */
          #custom-virtual-headset,
          #network
          /* , #clock */ {
            border-top-left-radius: 0;
            border-bottom-left-radius: 0;
            padding-left: 3px;
            border-left: none;
          }

          /* CUSTOM OVERRIDES/FIXES */
          /* fix right most module having a margin right */
          #clock {
            margin-right: 0;
          }

          /*shift to bottom*/
          #cava {
            padding-top: 6px;
            padding-bottom: 0px;
          }

          /* buttons come with their own padding */
          #workspaces {
            padding-left: 3px;
            padding-right: 3px;
          }

          #workspaces button {
            border: none;
            color: white;
            padding: 0;
            padding-left: 3px;
            padding-right: 6px;
            border-radius: 4px;
          }
          #workspaces button:hover {
            background: rgba(255, 255, 255, 0.5);
            border: none;
          }

          #custom-notification {
            /*should be inherited, so no change*/
            padding-left: 8px;
          }
          /* no notifications */
          #custom-notification.none {
            padding-right: 10px;
          }
          /* decrease padding to try and mantain width when notification icon active */
          #custom-notification.notification {
            padding-right: 3px; /* a relative change of 7px */
          }

          /*no notifications in dnd. trying to make it so toggling dnd does not cause shift, too*/
          #custom-notification.dnd-none {
            padding-left: 5px;
            padding-right: 13px;
          }
          /*
          * dnd with notification icon to try and maintain position with notification active;
          * it should be the same relative diferrence between .none and .notification padding right */
          #custom-notification.dnd-notification {
            padding-right: 6px;
            /* but also include the dnd icon size spacing fix...*/
            padding-left: 5px;
          }
          /*
          * so all of the above perfectly mantain the notification module width!
          * the only bad thing is the actual notification dot thing shift between dnd and normal,
          * but I guess that is okay for now */

          /*more spacing fixes*/
          #custom-arch {
            padding-left: 6px;
            padding-right: 13px;
          }

          /* make it more visible people can hear me */
          @keyframes pulse {
            0% {
              text-shadow: 0px 0px 4px rgba(255, 200, 200, 0.25);
              color: rgba(255, 150, 150, 1);
            }
            50% {
              text-shadow: 0px 0px 8px rgba(255, 200, 200, 1);
              color: rgba(255, 50, 50, 1);
            }
            100% {
              text-shadow: 0px 0px 4px rgba(255, 200, 200, 0.25);
              color: rgba(255, 150, 150, 1);
            }
          }

          #custom-virtual-headset.unmuted {
            animation: pulse 2s ease-in-out infinite;
          }
        '';
    };
  };
}
