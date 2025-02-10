{
  config,
  inputs,
  lib,
  pkgs,
  toplevel,
  ...
}:
let
  cfg = config.programs.waybar;
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
  config = {
    home.packages =
      # audio visualizer
      lib.optional (builtins.elem "cava" waybar-modules) pkgs.cava;

    programs.waybar = {
      # https://github.com/elythh/nixdots/blob/58db47f160c219c3e2a9630651dfd9aab0408b1a/modules/home/opt/wayland/services/swaync/default.nix
      enable = true;
      package = inputs.waybar.packages.${pkgs.system}.default;
      settings = {
        mainBar = import ./config.nix { inherit lib pkgs toplevel; };
      };
      style = builtins.readFile ./style.css;
    };
  };
}
