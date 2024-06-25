{ pkgs, ... }:
{
  imports = [
    ./programs/alacritty
    # ./programs/atuin
    ./programs/bat
    ./programs/direnv
    ./programs/eza
    # ./programs/firefox
    ./programs/git
    ./programs/kitty
    ./programs/lf
    ./programs/moar
    ./programs/mpv
    ./programs/neovide
    ./programs/nvim
    ./programs/starship
    # ./programs/swaynotificationcenter
    # ./programs/waybar
    ./programs/wezterm
    ./programs/zellij
    ./programs/zsh
  ];
  programs = {
    btop.enable = true;
    fzf.enable = true;
    jq.enable = true;
    ripgrep.enable = true;
    thefuck.enable = true;
    watson.enable = true;
    zoxide.enable = true;
  };
  home = {
    packages =
      with pkgs;
      [
        curl
        delta
        fd
        ffmpeg
        go-jira
        gh
        gnumake
        (jira-cli-go.overrideAttrs (oldAttrs: {
          postInstall = ''
            mv $out/bin/jira $out/bin/jira-unfree
          '';
        }))
        jless
        magic-wormhole-rs # send files easily
        neovide
        uair
        unzip
        tldr
        tree
        wget
        zip
      ]
      # custom packages
      ++ [
        cache-command
        ff
        generate-kaomoji
        is-sshed
        j
        jira-list
        jira-task-list
        notify
        nvim
        searcher
        uair-toggle-and-notify
        zellij-tab-name-update
      ]
      ++ [ ollama ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
      HSTR_CONFIG = "hicolor"; # get more colors
      HISTCONTROL = "ignorespace"; # leading space hides commands from history
      HISTFILESIZE = 100000; # increase history file size (default is 500)
      PATH = "$HOME/.config/scripts/:$PATH";
    };
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
  home.file.".config/scripts/localip".source = ./dotfiles/localip;
  # There has got to be a better way to do this :(
  home.file.".config/scripts/timeUtils.sh".source = ./dotfiles/timeUtils.sh;
  home.file.".config/scripts/colorUtils.sh".source = ./dotfiles/colorUtils.sh;
  home.file.".config/scripts/generate_tokens.sh".source = ./dotfiles/generate_tokens.sh;
  home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;
  home.file.".config/gh-dash/config.yml".source = ./dotfiles/gh-dash/config.yml;
  home.file.".config/uair/uair.toml".source = ./dotfiles/uair.toml;
  home.file.".config/pijul/config.toml".source = ./dotfiles/pijul/config.toml;
}
