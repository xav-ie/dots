{
  pkgs,
  pwnvim,
  ...
} @ inputs: {
  home = {
    packages = [pkgs.ripgrep pkgs.fd pkgs.curl pkgs.eza pwnvim.packages."aarch64-darwin".default];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      PAGER = "bat";
      EDITOR = "nvim";
    };
  };
  programs = {
    bat = {
      enable = true;
      config.theme = "TwoDark";
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    git = {enable = true;};
    zsh = {
      enable = true;
      enableCompletion = true;
      enableAutosuggestions = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ls = "exa";
      };
    };
    starship = {
      enable = true;
      enableZshIntegration = true;
    };
    alacritty = {
      enable = true;
      settings.font.normal.family = "MesloLGS Nerd Font Mono";
      settings.fontSize = 22;
    };
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
}
