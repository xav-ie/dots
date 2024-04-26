{ ... }:
{
  # https://github.com/elythh/nixdots/blob/58db47f160c219c3e2a9630651dfd9aab0408b1a/modules/home/opt/wayland/services/swaync/default.nix
  programs = {
    waybar = {
      enable = true;
      settings = {
        mainBar = import ./config.nix;
      };
      style = builtins.readFile (./. + "/style.css");
    };
  };
  # not sure if I still need this
  # (waybar.overrideAttrs (oldAttrs: {
  #   mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
  #   hyprlandSupport = true;
  # }))
}
