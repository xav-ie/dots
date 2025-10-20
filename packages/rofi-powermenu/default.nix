{
  lib,
  pkgs,
  writeNuApplication,
  writeText,
  rofi,
  hyprlock,
  hyprland,
  systemd,
}:
let
  theme = import ./theme.nix { inherit lib pkgs; };
  themeFile = writeText "rofi-powermenu-theme.rasi" theme;
in
writeNuApplication {
  name = "rofi-powermenu";
  runtimeInputs = [
    rofi
    hyprlock
    hyprland
    systemd
  ];
  runtimeEnv = {
    ROFI_POWERMENU_THEME = "${themeFile}";
  };
  text = builtins.readFile ./powermenu.nu;
}
