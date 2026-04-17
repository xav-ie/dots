{ lib, pkgs, ... }:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
  inherit (fonts.configs.gtk) name size;
  # QFont::toString format: family,pointsize,-1,5,weight,italic,underline,strikeout,fixedpitch,rawmode
  qtFont = family: ''"${family},${toString size},-1,5,50,0,0,0,0,0"'';
in
{
  config = {
    qt = {
      enable = true;
      platformTheme.name = "qtct";
      style.name = "kvantum-dark";

      qt6ctSettings = {
        Appearance.style = "kvantum-dark";
        Fonts.general = qtFont name;
      };
      qt5ctSettings = {
        Appearance.style = "kvantum-dark";
        Fonts.general = qtFont name;
      };
    };

    home.packages = with pkgs; [
      libsForQt5.qtstyleplugin-kvantum
      kdePackages.qtstyleplugin-kvantum
    ];

    # xdg-desktop-portal-hyprland is D-Bus activated under systemd --user, so
    # home.sessionVariables (which only writes shell rc files) never reaches
    # it. Also, home-manager's "qtct" platformTheme defaults to qt5ct in the
    # systemd env — hyprland-share-picker is Qt6, so it ignores qt5ct entirely.
    # mkForce to override the default and point Qt6 apps at qt6ct.
    systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME = lib.mkForce "qt6ct";

    xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
      [General]
      theme=KvGnomeDark
    '';
  };
}
