{ lib, pkgs, ... }:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;

  zellij-bin = lib.getExe pkgs.zellij;
in
{
  config = {
    programs.alacritty = {
      enable = true;
      settings = {
        # no ligatures lol: https://github.com/alacritty/alacritty/issues/50
        font.normal.family = fonts.name "mono";
        font.size = 16;
        window = {
          decorations = "None";
          opacity = 0.8;
          blur = true;
          #option_as_alt = "Both";
        };
        general.import = lib.optional pkgs.stdenv.isLinux pkgs.alacritty-theme.monokai_charcoal;
        keyboard.bindings = [
          {
            key = "Tab";
            mods = "Control";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "go-to-next-tab"
              ];
            };
          }
          {
            key = "Tab";
            mods = "Control|Shift";
            command = {
              program = "zellij";
              args = [
                "action"
                "go-to-previous-tab"
              ];
            };
          }
          {
            key = "o";
            mods = "Control|Shift";
            command = {
              program = "zellij";
              args = [
                "action"
                "switch-mode"
                "session"
              ];
            };
          }
          {
            key = "Tab";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "focus-next-pane"
              ];
            };
          }
          {
            key = "Tab";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "focus-previous-pane"
              ];
            };
          }
          {
            key = "h";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "move-focus-or-tab"
                "left"
              ];
            };
          }
          {
            key = "j";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "move-focus"
                "down"
              ];
            };
          }
          {
            key = "k";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "move-focus"
                "up"
              ];
            };
          }
          {
            key = "l";
            mods = "Alt|Shift";
            command = {
              program = zellij-bin;
              args = [
                "action"
                "move-focus-or-tab"
                "right"
              ];
            };
          }
        ];
      };
    };
  };
}
