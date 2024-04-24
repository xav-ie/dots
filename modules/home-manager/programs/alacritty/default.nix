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
        font.normal.family = "FiraCode Nerd Font Ret";
        # Hack has better spacing and numbers than Fira, 
        # but has worse special characters. Fira has some cool letters but both
        # have letter spacing problems "ma" "wa" both look bad when not italic
        # font.normal.family = "Hack Nerd Font";
        font.size = 14;
        window = {
          #decorations = "Transparent";
          opacity = 0.9;
          blur = true;
          #option_as_alt = "Both";
        };
        import = [ pkgs.alacritty-theme.iterm ];
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
              program = "zellij";
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
              program = "zellij";
              args = [
                "action"
                "focus-previous-pane"
              ];
            };
          }
        ];
      };
    };
  };
}
