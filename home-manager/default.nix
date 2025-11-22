{
  inputs,
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
    ./programs/claude
    ./programs/direnv
    ./programs/eza
    # ./programs/firefox
    ./programs/ghostty
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
    ./programs/plover
    ./programs/ssh
    ./programs/starship
    # ./programs/swaynotificationcenter
    ./programs/transmission
    # ./programs/waybar
    # ./programs/wezterm
    ./programs/wstunnel-ssh
    ./programs/yt-dlp
    # ./programs/zellij
    ./programs/zsh
  ];

  config = {
    programs = {
      btop.enable = true;
      # excellent completions that are fast
      # https://carapace-sh.github.io/carapace-bin/
      carapace.enable = true;
      carapace.package = pkgs.pkgs-bleeding.carapace;
      claude.enable = true;
      claude.nativeInstall = false;
      fzf.enable = true;
      jq.enable = true;
      jujutsu.enable = true;
      pay-respects.enable = true;
      ripgrep.enable = true;
      watson.enable = true;
      zoxide.enable = true;
      zoxide.package = pkgs.pkgs-bleeding.zoxide;
      yazi.enable = true;
    };
    home = {
      packages =
        (with pkgs; [
          pstree
          curl
          deadnix # dead code linter
          delta
          dig
          fd
          # a wrapper around ffmpeg that adds a progress bar and ETA
          ffpb
          ffmpeg
          generate-kaomoji
          gh
          gnumake
          go-jira
          hyperfine # perfomance tester
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
          nodejs
          nix-output-monitor # better nix build
          tldr
          tree
          uair # pomodoro manager
          (ueberzugpp.override {
            enableOpencv = false;
          })
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
          gp
          is-sshed
          j
          jira-list
          jira-task-list
          localip
          pgpod
          notify
          nix-repl
          nvim
          prs
          pr-summary
          review
          searcher
          tmux-tab-name-update
          toggle-theme
          uair-toggle-and-notify
          update-package-lock
          update-pr
          whisper-transcribe
          zellij-tab-name-update
        ])
        ++ [
          inputs.nix-auto-follow.packages.${pkgs.system}.default
        ];

      # The state version is required and should stay at the version you
      # originally installed.
      stateVersion = "23.11";
      sessionVariables = {
        EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
        # get more colors
        HSTR_CONFIG = "hicolor";
        # ignore both leading space commands and re-run commands from history
        HISTCONTROL = "ignoreboth";
        # increase history file size (default is 500)
        HISTFILESIZE = 100000;
        PATH = "$HOME/.config/scripts:$HOME/.npm/bin:$PATH";
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
    services = {
      ollama = {
        enable = true;
        package =
          if pkgs.stdenv.isDarwin then
            pkgs.pkgs-bleeding.ollama
          else
            pkgs.ollama.overrideAttrs (_oldAttrs: {
              version = "0.11.3";
              src = pkgs.fetchFromGitHub {
                owner = "ollama";
                repo = "ollama";
                tag = "v0.11.3";
                hash = "sha256-FghgCtVQIxc9qB5vZZlblugk6HLnxoT8xanZK+N8qEc=";
                fetchSubmodules = true;
              };
              vendorHash = "sha256-SlaDsu001TUW+t9WRp7LqxUSQSGDF1Lqu9M1bgILoX4=";
            });
      };
    };
  };
}
