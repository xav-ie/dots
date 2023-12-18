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
    alacritty = {
      enable = true;
      settings.font.normal.family = "MesloLGS Nerd Font Mono";
      settings.fontSize = 22;
    };
    bat = {
      enable = true;
      config.theme = "TwoDark";
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    git = {enable = true;};
    gh = {
      enable = true;
      extensions = [pkgs.gh-dash];
    };
    starship = {
      enable = true;
      enableZshIntegration = true;
    };
    zoxide = {enable = true;};
    zsh = {
      enable = true;
      enableCompletion = true;
      enableAutosuggestions = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ls = "exa";
      };
    };
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
}
