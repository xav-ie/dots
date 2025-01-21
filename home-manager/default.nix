{ pkgs, ... }:
{
  imports = [
    ./dotfiles
    ./programs/alacritty
    # ./programs/atuin
    ./programs/bat
    ./programs/direnv
    ./programs/eza
    # ./programs/firefox
    ./programs/git
    # ./programs/kitty
    # ./programs/lf
    ./programs/moar
    ./programs/mpv
    ./programs/neovide
    ./programs/ov
    ./programs/nvim
    ./programs/nushell
    ./programs/starship
    # ./programs/swaynotificationcenter
    # ./programs/transmission
    # ./programs/waybar
    # ./programs/wezterm
    ./programs/zellij
    ./programs/zsh
  ];

  config = {
    programs = {
      btop.enable = true;
      # excellent completions that are fast
      # https://carapace-sh.github.io/carapace-bin/
      carapace.enable = true;
      fzf.enable = true;
      jq.enable = true;
      ripgrep.enable = true;
      thefuck.enable = true;
      watson.enable = true;
      zoxide.enable = true;
    };
    home = {
      packages = with pkgs; [
        curl
        deadnix # dead code linter
        delta
        devenv # idk... I think I like plain flake approach
        fd
        ffmpeg
        go-jira
        gh
        gnumake
        (jira-cli-go.overrideAttrs {
          postInstall = ''
            mv $out/bin/jira $out/bin/jira-unfree
          '';
        })
        jless # best JSON and YAML viewer
        just # better make
        magic-wormhole-rs # send files easily
        nix-output-monitor # better nix build
        neovide
        ollama
        uair # pomodoro manager
        unzip
        tldr
        tree
        wget
        yazi # better lf
        zip
        # custom packages
        cache-command
        ff
        generate-kaomoji
        is-sshed
        j
        jira-list
        jira-task-list
        move-active
        notify
        nvim
        searcher
        uair-toggle-and-notify
        zellij-tab-name-update
      ];
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
    home.file.".inputrc".source =
      builtins.toFile "inputrc" # readline
        ''
          set show-all-if-ambiguous on
          set completion-ignore-case on
          set mark-directories on
          set mark-symlinked-directories on
          set match-hidden-files off
          set visible-stats on
          set keymap vi
          set editing-mode vi-insert
        '';
    home.file.".config/scripts/localip".source = ./dotfiles/localip.sh;
    # There has got to be a better way to do this :(
    home.file.".config/scripts/timeUtils.sh".source = ./dotfiles/timeUtils.sh;
    home.file.".config/scripts/colorUtils.sh".source = ./dotfiles/colorUtils.sh;
    home.file.".config/scripts/generate_tokens.sh".source = ./dotfiles/generate_tokens.sh;
    home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;
    home.file.".config/gh-dash/config.yml".source = ./dotfiles/gh-dash/config.yml;
    home.file.".config/uair/uair.toml".source = ./dotfiles/uair.toml;
    home.file.".config/pijul/config.toml".source = ./dotfiles/pijul/config.toml;
  };
}
