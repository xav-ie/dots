{ lib, pkgs, ... }:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
in
{

  config = {
    programs.kitty = {
      enable = true;
      keybindings = {
        "alt+h" = ''send_text all \x1bh'';
        "alt+j" = ''send_text all \x1bj'';
        "alt+k" = ''send_text all \x1bk'';
        "alt+l" = ''send_text all \x1bl'';
      };
      settings = {
        background = "#0a0a0f";
        background_blur = 10;
        background_opacity = "0.80";
        clipboard_control = "write-clipboard write-primary read-clipboard read-primary";
        copy_on_select = "yes";
        cursor = "#ff0000";
        font_family = fonts.name "mono";
        font_size = "13.0";
        hide_window_decorations = "yes";
        macos_quit_when_last_window_closed = "yes";
      };

      # kitty +list-fonts --psnames | grep Maple
      extraConfig =
        let
          fontName = lib.replaceChars [ " " ] [ "" ] (fonts.name "mono");
          mapleFontFeatures = lib.concatMapStringsSep " " (thing: "+" + thing) (fonts.features "mono");
        in
        ''
          font_features ${fontName}-Bold ${mapleFontFeatures}
          font_features ${fontName}-BoldItalic ${mapleFontFeatures}
          font_features ${fontName}-Italic ${mapleFontFeatures}
          font_features ${fontName}-Light ${mapleFontFeatures}
          font_features ${fontName}-LightItalic ${mapleFontFeatures}
          font_features ${fontName}-Regular ${mapleFontFeatures}
        '';
    };
    home.sessionVariables = {
      TERMINAL = "kitty";
    };
  };
}
