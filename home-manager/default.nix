{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ../lib/common/user.nix
    ./modules
  ];

  config = {
    programs = {
      # system monitor
      btop.enable = true;
      # excellent completions that are fast
      # https://carapace-sh.github.io/carapace-bin/
      carapace.enable = true;
      # AI chat client
      claude.enable = true;
      claude.nativeInstall = false;
      # fuzzy finder
      fzf.enable = true;
      # json processor
      jq.enable = true;
      # A user-friendly VCS
      jujutsu.enable = true;
      # automatic merge conflicts resolver
      mergiraf.enable = true;
      # f
      pay-respects.enable = true;
      # autonomous AI agent loop
      ralph.enable = true;
      # fast grep
      ripgrep.enable = true;
      # a more featureful fzf
      television.enable = true;
      # python package manager
      uv.enable = true;
      # time tracker
      watson.enable = true;
      # cd supercharged
      zoxide.enable = true;
      # file manager
      yazi.enable = true;
    };
    home = {
      packages =
        (with pkgs; [
          pstree
          curl
          deadnix # dead code linter
          devenv
          dig
          fd
          # a wrapper around ffmpeg that adds a progress bar and ETA
          ffpb
          ffmpeg
          generate-kaomoji
          gh
          git-absorb
          gnumake
          go-jira
          hyperfine # perfomance tester
          imagemagick
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
          format-staged
          gp
          is-sshed
          j
          jira-list
          jira-task-list
          lint-staged
          localip
          nix-repl
          nom-run
          notify
          nvim
          pgpod
          pr-summary
          prs
          review
          searcher
          tmux-move-window
          tmux-tab-name-update
          toggle-theme
          uair-toggle-and-notify
          update-package-lock
          update-pr
          whisper-transcribe
          zellij-tab-name-update
        ])
        ++ [
          inputs.nix-auto-follow.packages.${pkgs.stdenv.hostPlatform.system}.default
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
    xdg.enable = true;
  };
}
