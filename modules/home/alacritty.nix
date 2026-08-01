{
  flake.modules.homeManager.common =
    {
      lib,
      pkgs,
      fonts,
      ...
    }:
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
          };
        };
      };
    };
}
