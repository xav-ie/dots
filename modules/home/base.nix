# Cross-platform home-manager program toggles and package set.
{
  flake.modules.homeManager.common =
    {
      inputs,
      pkgs,
      ...
    }:
    {
      config = {
        programs = {
          # git-backed graph issue tracker for AI agents
          beads.enable = false;
          bun.enable = true;
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
          # GitHub CLI + declaratively-managed extensions
          gh = {
            enable = true;
            extensions = [ pkgs.gh-markdown-preview ];
            settings.git_protocol = "ssh";
          };
          # json processor
          jq.enable = true;
          gemini.enable = true;
          # nodejs + declarative npm global package sync
          npm.enable = true;
          orca-slicer.enable = true;
          # A user-friendly VCS
          jujutsu.enable = true;
          # pi coding agent
          pi = {
            enable = true;
            extensions = with pkgs.pkgs-mine; [
              pi-executor
              pi-readcache
              pi-show-diffs
            ];
          };
          # automatic merge conflicts resolver
          mergiraf.enable = true;
          # autonomous AI agent loop
          ralph.enable = true;
          # fast grep
          ripgrep.enable = true;
          # a more featureful fzf
          television.enable = true;
          # python package manager
          uv.enable = true;
          uv.tools.enable = true;
          # time tracker
          watson.enable = true;
          # cd supercharged
          zoxide.enable = true;
          # we define `z`/`zi`/`zf` ourselves in nushell config.nu (with skim
          # fall-through); --no-cmd keeps zoxide's dir-tracking hook but drops its
          # own z/zi aliases, which would otherwise load *after* and shadow ours.
          zoxide.options = [ "--no-cmd" ];
          # file manager
          yazi.enable = true;
          worktrunk.enable = true;
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
              git-absorb
              gnumake
              go-jira
              hyperfine # performance tester
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
              nix-output-monitor # better nix build
              pnpm
              skim # fuzzy finder (sk) — used by `zf`
              tldr
              tree
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
              clauhist
              ff
              firefox-router
              flint
              format-staged
              gp
              is-sshed
              lint-staged
              localip
              nix-flamegraph
              nix-repl
              nom-run
              notify
              nvim
              osgrep-indexed
              pgpod
              pr-summary
              prs
              review
              searcher
              tm
              tmux-move-window
              tmux-tab-name-update
              toggle-theme
              tsc-filter
              uair-toggle-and-notify
              update-package-lock
              update-pr
              whisper-transcribe
              zellij-tab-name-update
            ])
            ++ [
              inputs.nix-auto-follow.packages.${pkgs.stdenv.hostPlatform.system}.default
              inputs.openspec.packages.${pkgs.stdenv.hostPlatform.system}.default
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
            PATH = "$HOME/.local/bin:$HOME/.config/scripts:$HOME/.npm/bin:$PATH";
          };
        };
        xdg.enable = true;
      };
    };
}
