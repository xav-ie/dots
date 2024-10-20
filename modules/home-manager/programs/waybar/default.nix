{ inputs, pkgs, ... }:
{
  config = {
    programs.waybar = {
      # https://github.com/elythh/nixdots/blob/58db47f160c219c3e2a9630651dfd9aab0408b1a/modules/home/opt/wayland/services/swaync/default.nix
      enable = true;
      package = inputs.waybar.packages.${pkgs.system}.default;
      settings = {
        mainBar = import ./config.nix;
      };
      style = builtins.readFile (./. + "/style.css");
    };
  };
}
