{
  pkgs,
  ...
} @ inputs: {
  home = {
    packages = [pkgs.yabai pkgs.wezterm];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
    };
  };
  programs = {
    alacritty = {
      enable = true;
      settings = {
        font.normal.family = "MesloLGS Nerd Font Mono";
        font.size = 14;
        window = {
          decorations = "Transparent"; # "Transparent" is mac only
          opacity = 0.9;
          blur = true; # does not seem to work...
          #option_as_alt = "Both"; # mac only
        };
      };
    };
    zsh = {
      initExtra = '' '';
    };
  };
  home.file.".config/borders/bordersrc".source = ./dotfiles/bordersrc;
  home.file.".config/wezterm/wezterm.lua".source = ./dotfiles/wezterm.lua;
}
