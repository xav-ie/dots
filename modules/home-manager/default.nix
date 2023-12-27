{
  pkgs,
  zjstatus,
  ...
} @ inputs: let
  # there is no difference in output...? Idk if there is good reason to use one over the other
  #zjstatus_package = inputs.zjstatus.outputs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  zjstatus_package = inputs.zjstatus.outputs.packages.${pkgs.system}.default;
  # see https://github.com/dj95/zjstatus
  # for some reason, I could not figure out pkgs.zjstatus
  default_tab_template = ''
    default_tab_template {
        children
        pane size=1 borderless=true {
            plugin location="file:${zjstatus_package}/bin/zjstatus.wasm" {
              format_left  "{mode} #[fg=#FA89B4,bold]{session} {tabs}"
              format_right "{datetime}"
              format_space ""
              border_enabled  "false"
              border_char     "─"
              border_format   "#[fg=#6C7086]{char}"
              border_position "top"
              mode_normal        "#[bg=magenta] "
              mode_locked        "#[bg=black] {name} "
              mode_locked        "#[bg=black] {name} "
              mode_resize        "#[bg=black] {name} "
              mode_pane          "#[bg=black] {name} "
              mode_tab           "#[bg=black] {name} "
              mode_scroll        "#[bg=black] {name} "
              mode_enter_search  "#[bg=black] {name} "
              mode_search        "#[bg=black] {name} "
              mode_rename_tab    "#[bg=black] {name} "
              mode_rename_pane   "#[bg=black] {name} "
              mode_session       "#[bg=black] {name} "
              mode_move          "#[bg=black] {name} "
              mode_prompt        "#[bg=black] {name} "
              mode_tmux          "#[bg=red] {name} "
              tab_normal   "#[fg=#6C7086] {name} "
              tab_active   "#[fg=magenta,bold,italic] {name} "
              datetime        "#[fg=cyan,bold] {format} "
              datetime_format "%A, %d %b %Y %I:%M %p"
              datetime_timezone "America/New_York"
            }
        }
    }
  '';
in {
  home = {
    packages = with pkgs; [ripgrep fd curl eza delta];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      BROWSER = "qutebrowser";
      EDITOR = "nvim";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      PAGER = "bat";
      TERMINAL = "alacritty";
      # get more colors
      HSTR_CONFIG = "hicolor";
      # leading space hides commands from history
      HISTCONTROL = "ignorespace";
      # increase history file size (default is 500)
      HISTFILESIZE = 10000;
      PATH = "$HOME/.config/scripts/:$PATH";
    };
  };
  programs = {
    alacritty = {
      enable = true;
      settings = {
        font.normal.family = "MesloLGS Nerd Font Mono";
        font.size = 14;
        window = {
          #decorations = "Transparent";
          opacity = 0.9;
          blur = true;
          #option_as_alt = "Both";
        };
      };
    };
    bat = {
      enable = true;
      config.theme = "TwoDark";
    };

    direnv = {
      enable = true;
      # very important, allows caching of build-time deps
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    git = {
      enable = true;
      userName = "xav-ie";
      userEmail = "xruizify@gmail.com";
      aliases = {
        graph = "log --graph --pretty=tformat:'%C(bold blue)%h%Creset %s %C(bold green)%d%Creset %C(blue)<%an>%Creset %C(dim cyan)%cr' --abbrev-commit --decorate";
      };
      extraConfig = {
        core = {
          pager = "delta";
        };
        interactive = {
          diffFilter = "delta --color-only";
        };
        delta = {
          navigate = true;
          line-numbers = true;
          true-color = "always";
        };
        merge = {
          conflictstyle = "diff3";
        };
        diff = {
          colorMoved = "default";
        };
      };
    };
    gh = {
      enable = true;
      extensions = [pkgs.gh-dash];
    };
    lf = {
      enable = true;
      # TODO: add a lot more config
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
    watson = {
      enable = true;
    };
    zoxide = {enable = true;};
    zellij = {
      enable = true;
    };
    zsh = {
      enable = true;
      enableCompletion = true;
      enableAutosuggestions = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        gd = "git diff --ignore-all-space --ignore-space-at-eol --ignore-space-change --ignore-blank-lines -- . ':(exclude)*package-lock.json' -- . ':(exclude)*yarn.lock'";
        gpr = "GH_FORCE_TTY=100% gh pr list | fzf --ansi --preview 'GH_FORCE_TTY=100% gh pr view {1}' --preview-window up --header-lines 3 | awk '{print \$1}' | xargs gh pr checkout";
        ls = "exa";
        main = "git fetch && git fetch --tags && git checkout -B main origin/main";
        n = "NIXPKGS_ALLOW_UNFREE=1 exec nix shell --impure nixpkgs#nodejs-18_x nixpkgs#yarn nixpkgs#cloudflared nixpkgs#terraform nixpkgs#google-cloud-sdk nixpkgs#bun nixpkgs#nodePackages.\"prettier\" nixpkgs#deno nixpkgs#prettierd";
        w = "watson";
      };
      initExtra = ''
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

        # TODO: get tab name update scripts and others
        #export PROMPT_COMMAND="$HOME/.config/scripts/zellij_tab_name_update.sh; $PROMPT_COMMAND"
        source ~/.env


      '';
    };
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
  home.file.".config/scripts/localip".source = ./dotfiles/localip;
  # There has got to be a better way to do this :(
  home.file.".config/scripts/timeUtils.sh".source = ./dotfiles/timeUtils.sh;
  home.file.".config/scripts/colorUtils.sh".source = ./dotfiles/colorUtils.sh;
  home.file.".config/scripts/jiraIssues.sh".source = ./dotfiles/jiraIssues.sh;
  home.file.".config/scripts/generate_tokens.sh".source = ./dotfiles/generate_tokens.sh;
  home.file.".config/scripts/zellij_tab_name_update.sh".source = ./dotfiles/zellij_tab_name_update.sh;
  home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;

  home.file.".config/zellij/config.kdl".source = ./dotfiles/zellij/config.kdl;
  home.file.".config/zellij/layouts/default.kdl".text = ''
    layout {
        ${default_tab_template}
        tab
    }
  '';
}
