{ pkgs, ... }: {
  imports = [
    ./programs/zellij/default.nix
  ];
  home = {
    packages = with pkgs; [
      curl
      delta
      eza
      fd
      gh
      gnumake
      jq
      magic-wormhole-rs # send files easily
      ripgrep
      unzip
      zip
    ];
    # The state version is required and should stay at the version you
    # originally installed.
    stateVersion = "23.11";
    sessionVariables = {
      BROWSER = "qutebrowser";
      EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
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
    btop.enable = true;
    direnv = {
      enable = true;
      # very important, allows caching of build-time deps
      nix-direnv.enable = true;
    };
    eza = {
      enable = true;
      enableAliases = true;
      git = true;
      icons = true;
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
      # I am guessing this option sets up the options I set in extraConfig
      delta = {
        enable = true;
        options = {
          navigate = true;
          line-numbers = true;
          true-color = "always";
        };
      };
      extraConfig = {
        core = {
          # configured by delta.enable=true
          # pager = "delta";
        };
        interactive = {
          # configured by delta.enable=true
          # diffFilter = "delta --color-only";
        };
        # configured by delta.enable=true
        # delta = {
        #   navigate = true;
        #   line-numbers = true;
        #   true-color = "always";
        # };
        merge = {
          conflictstyle = "diff3";
        };
        diff = {
          colorMoved = "default";
        };
      };
    };
    #gh = {
    #  enable = true;
    #  extensions = [pkgs.gh-dash];
    #};
    # heavily borrowed from https://www.youtube.com/watch?v=z8y_qRUYEWU
    lf = {
      enable = true;
      commands = {
        dragon-out = ''%${pkgs.xdragon}/bin/xdragon -a -x "$fx"'';
        editor-open = ''$$EDITOR $f'';
        mkdir = '' ''${{
	  printf "Directory Name: "
	  read DIR
	  mkdir $DIR
	}}'';
      };
      keybindings = {
        # ?
        "\\\"" = "";
        o = "open";
        c = "mkdir";
        "." = "set hidden!";
        "`" = "mark-load";
        "\\'" = "mark-load";
        "<enter>" = "editor-open";
        do = "dragon-out";
        "g~" = "cd";
        gh = "cd";
        "g/" = "/";
        ee = "editor-open";
        # TODO: make this work only when you have file selected. otherwise, enter folder
        # l = "editor-open";
        V = ''''$${pkgs.bat}/bin/bat --paging always "$f"'';
      };
      settings = {
        preview = true;
        hidden = true;
        drawbox = true;
        icons = true;
        ignorecase = true;

        previewer = "${pkgs.ctpv}/bin/ctpv";
        cleaner = "${pkgs.ctpv}/bin/ctpvclear";
      };
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
    zoxide = { enable = true; };
    zsh = {
      enable = true;
      enableCompletion = true;
      enableAutosuggestions = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        gc = "git commit";
        gcam = "gc -am";
        gd = "git diff --ignore-all-space --ignore-space-at-eol --ignore-space-change --ignore-blank-lines -- . ':(exclude)*package-lock.json' -- . ':(exclude)*yarn.lock'";
        gdc = "git diff --cached --ignore-all-space --ignore-space-at-eol --ignore-space-change --ignore-blank-lines -- . ':(exclude)*package-lock.json' -- . ':(exclude)*yarn.lock'";
        gp = "git push";
        gs = "git status";
        gpr = "GH_FORCE_TTY=100% gh pr list | fzf --ansi --preview 'GH_FORCE_TTY=100% gh pr view {1}' --preview-window up --header-lines 3 | awk '{print \$1}' | xargs gh pr checkout";
        #ls = "exa";
        main = "git fetch && git fetch --tags && git checkout -B main origin/main";
        n = "NIXPKGS_ALLOW_UNFREE=1 exec nix shell --impure nixpkgs#nodejs-18_x nixpkgs#yarn nixpkgs#cloudflared nixpkgs#terraform nixpkgs#google-cloud-sdk nixpkgs#bun nixpkgs#nodePackages.\"prettier\" nixpkgs#deno nixpkgs#prettierd";
        w = "watson";
        nvim = "~/Projects/xnixvim/result/bin/nvim";
        zj = "zellij attach || zellij";
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

        source $HOME/.env
        precmd() {
          $HOME/.config/scripts/zellij_tab_name_update.sh; 
        }
      '';
    };
  };
  home.file.".inputrc".source = ./dotfiles/inputrc;
  home.file.".config/lf/icons".source = ./dotfiles/icons;
  home.file.".config/scripts/localip".source = ./dotfiles/localip;
  # There has got to be a better way to do this :(
  home.file.".config/scripts/timeUtils.sh".source = ./dotfiles/timeUtils.sh;
  home.file.".config/scripts/colorUtils.sh".source = ./dotfiles/colorUtils.sh;
  home.file.".config/scripts/jiraIssues.sh".source = ./dotfiles/jiraIssues.sh;
  home.file.".config/scripts/generate_tokens.sh".source = ./dotfiles/generate_tokens.sh;
  home.file.".config/scripts/zellij_tab_name_update.sh".source = ./dotfiles/zellij_tab_name_update.sh;
  home.file.".config/scripts/remove_video_silence.py".source = ./dotfiles/remove_video_silence.py;
  home.file.".config/gh-dash/config.yml".source = ./dotfiles/gh-dash/config.yml;
}
