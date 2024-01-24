{ ... }: {
  home = {
    packages = [ ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = { };
  };
  programs = {
    zsh = {
      initExtra = '' '';
    };
  };
  home.file.".config/borders/bordersrc".source = ./dotfiles/bordersrc;
}
