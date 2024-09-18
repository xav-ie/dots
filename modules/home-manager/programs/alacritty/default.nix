{ pkgs, ... }:
{
  programs = {
    alacritty = {
      enable = true;
      settings = {
        # == === => ->
        # A lot like Lato, but mono
        # font.normal.family = "MonaspiceAr NF Medium";
        # not available yet, awaiting full test
        # font.normal.family = "Cartograph Nerd Font";
        font.normal.family = "Maple Mono";
        # Hack has better spacing and numbers than Fira, 
        # but has worse special characters. Fira has some cool letters but both
        # have letter spacing problems "ma" "wa" both look bad when not italic
        # font.normal.family = "Hack Nerd Font";
        font.size = 16;
        window = {
          decorations = "None";
          opacity = 0.8;
          blur = true;
          # startup_mode = "SimpleFullscreen";
          #option_as_alt = "Both";
        };
        import = [ pkgs.alacritty-theme.hyper ];
        # import = [ pkgs.alacritty-theme.papercolor_light ];
        keyboard.bindings = [
          {
            key = "Tab";
            mods = "Control";
            command = {
              program = "zellij";
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
            key = "Tab";
            mods = "Alt";
            command = {
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
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
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
              args = [
                "action"
                "focus-previous-pane"
              ];
            };
          }
          # TODO: make cross-platform
          {
            key = "h";
            mods = "Alt";
            command = {
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
              args = [
                "action"
                "move-focus-or-tab"
                "left"
              ];
            };
          }
          {
            key = "j";
            mods = "Alt";
            command = {
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
              args = [
                "action"
                "move-focus"
                "down"
              ];
            };
          }
          {
            key = "k";
            mods = "Alt";
            command = {
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
              args = [
                "action"
                "move-focus"
                "up"
              ];
            };
          }
          {
            key = "l";
            mods = "Alt";
            command = {
              program = "/etc/profiles/per-user/xavierruiz/bin/zellij";
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
