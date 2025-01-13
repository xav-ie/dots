_: {
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
        font_family = "Maple Mono";
        font_size = "13.0";
        hide_window_decorations = "yes";
        macos_quit_when_last_window_closed = "yes";
      };

      # kitty +list-fonts --psnames | grep Maple
      extraConfig =
        let
          mapleFontFeatures = "+cv01 +cv02 +cv04 +ss01 +ss02 +ss03 +ss04 +ss05";
        in
        ''
          font_features MapleMono-Bold ${mapleFontFeatures}
          font_features MapleMono-BoldItalic ${mapleFontFeatures}
          font_features MapleMono-Italic ${mapleFontFeatures}
          font_features MapleMono-Light ${mapleFontFeatures}
          font_features MapleMono-LightItalic ${mapleFontFeatures}
          font_features MapleMono-Regular ${mapleFontFeatures}
        '';
    };
    home.sessionVariables = {
      TERMINAL = "kitty";
    };
  };
}
