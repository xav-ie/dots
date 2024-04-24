{ pkgs, ... }:
{
  imports = [
    ./programs/alacritty
    ./programs/git
    ./programs/lf
    ./programs/zellij
  ];
  home = {
    packages =
      with pkgs;
      [
        curl
        delta
        eza
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
        jq
        magic-wormhole-rs # send files easily
        moar # the best pager
        ripgrep
        uair
        unzip
        tree
        wget
        zip
      ]
      ++ [
        # the shell I use most often
        # nodejs
        # cloudflared
        # python3
        # yarn
      ]
      ++ [
        # experimental
        # bun
        # deno
        ollama
      ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      BROWSER = "firefox";
      EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      # causes bug if set. dont do it!
      BAT_PAGER = "";
      PAGER = ''bat -p --pager=\"moar -quit-if-one-screen\" --terminal-width=$(expr $COLUMNS - 4)'';
      MOAR = "-quit-if-one-screen";
      TERMINAL = "wezterm";
      # get more colors
      HSTR_CONFIG = "hicolor";
      # leading space hides commands from history
      HISTCONTROL = "ignorespace";
      # increase history file size (default is 500)
      HISTFILESIZE = 10000;
      SOMETHING_RANDOM = 12;
      PATH = "$HOME/.config/scripts/:$PATH";
    };
  };
  programs = {
    atuin = {
      enable = true;
      enableZshIntegration = true;
      settings.style = "compact";
    };
    bat = {
      enable = true;
      config = {
        theme = "ansi";
        pager = "moar -quit-if-one-screen";
        paging = "auto";
        style = "plain";
        wrap = "character";
      };
    };
    btop.enable = true;
    direnv = {
      enable = true;
      # very important, allows caching of build-time deps
      nix-direnv.enable = true;
    };
    eza = {
      enable = true;
      enableZshIntegration = true;
      git = true;
      icons = true;
    };
    fzf = {
      enable = true;
      # testing out atuin instead
      # enableZshIntegration = true;
    };
    mpv = {
      enable = true;
    };
    starship = {
      enable = true;
      enableZshIntegration = true;
    };
    thefuck = {
      enable = true;
    };
    wezterm = {
      enable = true;
      extraConfig = # lua
        ''
          -- Pull in the wezterm API
          local wezterm = require 'wezterm'
          local mux = wezterm.mux

          wezterm.on("gui-startup", function()
            local tab, pane, window = mux.spawn_window{}
            window:gui_window():maximize()
          end)

          -- This table will hold the configuration.
          local config = {}

          -- In newer versions of wezterm, use the config_builder which will
          -- help provide clearer error messages
          if wezterm.config_builder then
            config = wezterm.config_builder()
          end

          -- This is where you actually apply your config choices

          -- For example, changing the color scheme:
          config = {
            window_background_opacity = 0.95,
            macos_window_background_blur = 0,
            color_scheme = 'Argonaut',
            window_decorations = "RESIZE",
            enable_tab_bar = false,
            -- use_fancy_tab_bar = false
            window_padding = {
              left = 0,
              right = 0,
              top = 0,
              bottom = 0,
            },
          }

          -- and finally, return the configuration to wezterm
          return config
        '';
    };
    watson = {
      enable = true;
    };
    zoxide = {
      enable = true;
    };
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        # this is for commands that do not properly adjust their output to given width
        c4 = "COLUMNS=$COLUMNS-4";
        info = "env info --vi-keys";
        # I could not get man to respect pager width
        man = "c4 env man";
        n = ''NIXPKGS_ALLOW_UNFREE=1 exec nix shell --impure nixpkgs#nodejs-18_x nixpkgs#yarn nixpkgs#cloudflared nixpkgs#terraform nixpkgs#google-cloud-sdk nixpkgs#bun nixpkgs#nodePackages."prettier" nixpkgs#deno nixpkgs#prettierd'';
        # nvim = "~/Projects/xnixvim/result/bin/nvim";
        w = "watson";
        zj = "zellij attach || zellij";
      };
      initExtra = # sh
        ''
          # comment this if you face weird direnv issues
          export DIRENV_LOG_FORMAT=""

          function git_diff_exclude_file() {
            if [ $# -lt 3 ]; then
              echo "Usage: git_diff_exclude_file <start_commit> <end_commit> <exclude_file> [output_file]"
              return 1
            fi

            local start_commit=$1
            local end_commit=$2
            local exclude_file=$3
            local output_file=$\{4:-combined_diff.txt}

            git diff --name-only "$start_commit" "$end_commit" | grep -v "$exclude_file" | xargs -I {} git diff "$start_commit" "$end_commit" -- {} > "$output_file"
          }

          source $HOME/.env

          precmd() {
            ${pkgs.zellij-tab-name-update}/bin/zellij-tab-name-update
          }

          download_nixpkgs_cache_index () {
            filename="index-$(uname -m | sed 's/^arm64$/aarch64/')-$(uname | tr A-Z a-z)"
            mkdir -p ~/.cache/nix-index && cd ~/.cache/nix-index
            # -N will only download a new version if there is an update.
            wget -q -N https://github.com/Mic92/nix-index-database/releases/latest/download/$filename
            ln -f $filename files
          }
        '';
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
}
