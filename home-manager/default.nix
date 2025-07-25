{
  pkgs,
  ...
}:
{
  imports = [
    ../lib/common/user.nix
    ./dotfiles
    ./programs/alacritty
    ./programs/atuin
    ./programs/bat
    ./programs/direnv
    ./programs/eza
    # ./programs/firefox
    ./programs/git
    ./programs/gpg
    ./programs/jujutsu
    # ./programs/kitty
    ./programs/pueue
    ./programs/moar
    ./programs/mpv
    ./programs/neovide
    ./programs/tmux
    ./programs/nushell
    ./programs/nvim
    ./programs/ov
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
      carapace.package = pkgs.pkgs-bleeding.carapace;
      fzf.enable = true;
      jq.enable = true;
      jujutsu.enable = true;
      ripgrep.enable = true;
      thefuck.enable = true;
      watson.enable = true;
      zoxide.enable = true;
      zoxide.package = pkgs.pkgs-bleeding.zoxide;
      yazi.enable = true;
    };
    home = {
      packages =
        (with pkgs; [
          curl
          deadnix # dead code linter
          delta
          dig
          pkgs-bleeding.devenv # idk... I think I like plain flake approach
          fd
          ffmpeg
          generate-kaomoji
          gh
          gnumake
          go-jira
          (jira-cli-go.overrideAttrs {
            postInstall = ''
              mv $out/bin/jira $out/bin/jira-unfree
            '';
          })
          jless # best JSON and YAML viewer
          just # better make
          lsof
          magic-wormhole-rs # send files easily
          neovide
          nix-output-monitor # better nix build
          ollama
          tldr
          tree
          uair # pomodoro manager
          ueberzugpp
          unzip
          wget
          zip
        ])
        # custom packages
        ++ (with pkgs.pkgs-mine; [
          apple-emoji-linux
          base-ref
          better-branch
          cache-command
          ff
          is-sshed
          j
          jira-list
          jira-task-list
          localip
          notify
          nix-repl
          nvim
          prs
          pr-summary
          review
          searcher
          tmux-tab-name-update
          uair-toggle-and-notify
          update-package-lock
          update-pr
          zellij-tab-name-update
        ]);

      # The state version is required and should stay at the version you
      # originally installed.
      stateVersion = "23.11";
      # TODO: how to re-source this in zsh?
      sessionVariables = {
        EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
        # get more colors
        HSTR_CONFIG = "hicolor";
        # ignore both leading space commands and re-run commands from history
        HISTCONTROL = "ignoreboth";
        # increase history file size (default is 500)
        HISTFILESIZE = 100000;
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
    # There has got to be a better way to do this :(
    home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;
    home.file.".config/gh-dash/config.yml".source = ./dotfiles/gh-dash/config.yml;
    home.file.".config/uair/uair.toml".source = ./dotfiles/uair.toml;
    home.file.".config/pijul/config.toml".source = ./dotfiles/pijul/config.toml;
    services = {
      gpg-agent = {
        enable = true;
        enableSshSupport = true;
      };
    };
  };
}
