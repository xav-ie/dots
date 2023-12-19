{
  pkgs,
  pwnvim,
  ...
} @ inputs: {
  home = {
    packages = [pwnvim.packages."aarch64-darwin".default];
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
  };
  #home.file.".inputrc".source = ./dotfiles/inputrc;
}
