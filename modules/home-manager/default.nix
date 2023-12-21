{pkgs, ...} @ inputs: let
  x = 3;
  # see https://github.com/dj95/zjstatus
  #  default_tab_template = ''
  #    default_tab_template {
  #        children
  #        pane size=1 borderless=true {
  #            plugin location="file:${pkgs.zjstatus}/bin/zjstatus.wasm" {
  #              format_left  "{mode} #[fg=#FA89B4,bold]{session} {tabs}"
  #              format_right "{datetime}"
  #              format_space ""
  #
  #              border_enabled  "false"
  #              border_char     "─"
  #              border_format   "#[fg=#6C7086]{char}"
  #              border_position "top"
  #
  #              mode_normal        "#[bg=magenta] "
  #              mode_locked        "#[bg=black] {name} "
  #              mode_locked        "#[bg=black] {name} "
  #              mode_resize        "#[bg=black] {name} "
  #              mode_pane          "#[bg=black] {name} "
  #              mode_tab           "#[bg=black] {name} "
  #              mode_scroll        "#[bg=black] {name} "
  #              mode_enter_search  "#[bg=black] {name} "
  #              mode_search        "#[bg=black] {name} "
  #              mode_rename_tab    "#[bg=black] {name} "
  #              mode_rename_pane   "#[bg=black] {name} "
  #              mode_session       "#[bg=black] {name} "
  #              mode_move          "#[bg=black] {name} "
  #              mode_prompt        "#[bg=black] {name} "
  #              mode_tmux          "#[bg=red] {name} "
  #
  #              tab_normal   "#[fg=#6C7086] {name} "
  #              tab_active   "#[fg=magenta,bold,italic] {name} "
  #
  #              datetime        "#[fg=cyan,bold] {format} "
  #              datetime_format "%A, %d %b %Y %I:%M %p"
  #              datetime_timezone "America/New_York"
  #            }
  #        }
  #    }
  #  '';
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

  home.file.".config/zellij/config.kdl".text = ''
    // If you'd like to override the default keybindings completely,
    // be sure to change "keybinds" to "keybinds clear-defaults=true"
    keybinds {
        normal {
            // uncomment this and adjust key if using copy_on_select=false
            // bind "Alt c" { Copy; }
        }
        locked {
            bind "Ctrl g" { SwitchToMode "Normal"; }
        }
        resize {
            bind "Ctrl n" { SwitchToMode "Normal"; }
            bind "h" "Left" { Resize "Increase Left"; }
            bind "j" "Down" { Resize "Increase Down"; }
            bind "k" "Up" { Resize "Increase Up"; }
            bind "l" "Right" { Resize "Increase Right"; }
            bind "H" { Resize "Decrease Left"; }
            bind "J" { Resize "Decrease Down"; }
            bind "K" { Resize "Decrease Up"; }
            bind "L" { Resize "Decrease Right"; }
            bind "=" "+" { Resize "Increase"; }
            bind "-" { Resize "Decrease"; }
        }
        pane {
            bind "Ctrl p" { SwitchToMode "Normal"; }
            bind "h" "Left" { MoveFocus "Left"; }
            bind "l" "Right" { MoveFocus "Right"; }
            bind "j" "Down" { MoveFocus "Down"; }
            bind "k" "Up" { MoveFocus "Up"; }
            bind "p" { SwitchFocus; }
            bind "n" { NewPane; SwitchToMode "Normal"; }
            bind "d" { NewPane "Down"; SwitchToMode "Normal"; }
            bind "r" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "x" { CloseFocus; SwitchToMode "Normal"; }
            bind "f" { ToggleFocusFullscreen; SwitchToMode "Normal"; }
            bind "z" { TogglePaneFrames; SwitchToMode "Normal"; }
            bind "w" { ToggleFloatingPanes; SwitchToMode "Normal"; }
            bind "e" { TogglePaneEmbedOrFloating; SwitchToMode "Normal"; }
            bind "c" { SwitchToMode "RenamePane"; PaneNameInput 0;}
        }
        move {
            bind "Ctrl h" { SwitchToMode "Normal"; }
            bind "n" "Tab" { MovePane; }
            bind "p" { MovePaneBackwards; }
            bind "h" "Left" { MovePane "Left"; }
            bind "j" "Down" { MovePane "Down"; }
            bind "k" "Up" { MovePane "Up"; }
            bind "l" "Right" { MovePane "Right"; }
        }
        tab {
            bind "Ctrl t" { SwitchToMode "Normal"; }
            bind "r" { SwitchToMode "RenameTab"; TabNameInput 0; }
            bind "h" "Left" "Up" "k" { GoToPreviousTab; }
            bind "l" "Right" "Down" "j" { GoToNextTab; }
            bind "n" { NewTab; SwitchToMode "Normal"; }
            bind "x" { CloseTab; SwitchToMode "Normal"; }
            bind "s" { ToggleActiveSyncTab; SwitchToMode "Normal"; }
            bind "1" { GoToTab 1; SwitchToMode "Normal"; }
            bind "2" { GoToTab 2; SwitchToMode "Normal"; }
            bind "3" { GoToTab 3; SwitchToMode "Normal"; }
            bind "4" { GoToTab 4; SwitchToMode "Normal"; }
            bind "5" { GoToTab 5; SwitchToMode "Normal"; }
            bind "6" { GoToTab 6; SwitchToMode "Normal"; }
            bind "7" { GoToTab 7; SwitchToMode "Normal"; }
            bind "8" { GoToTab 8; SwitchToMode "Normal"; }
            bind "9" { GoToTab 9; SwitchToMode "Normal"; }
            bind "Tab" { ToggleTab; }
        }
        scroll {
            bind "Ctrl s" { SwitchToMode "Normal"; }
            bind "e" { EditScrollback; SwitchToMode "Normal"; }
            bind "s" { SwitchToMode "EnterSearch"; SearchInput 0; }
            bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            // uncomment this and adjust key if using copy_on_select=false
            // bind "Alt c" { Copy; }
        }
        search {
            bind "Ctrl s" { SwitchToMode "Normal"; }
            bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
            bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "n" { Search "down"; }
            bind "p" { Search "up"; }
            bind "c" { SearchToggleOption "CaseSensitivity"; }
            bind "w" { SearchToggleOption "Wrap"; }
            bind "o" { SearchToggleOption "WholeWord"; }
        }
        entersearch {
            bind "Ctrl c" "Esc" { SwitchToMode "Scroll"; }
            bind "Enter" { SwitchToMode "Search"; }
        }
        renametab {
            bind "Ctrl c" { SwitchToMode "Normal"; }
            bind "Esc" { UndoRenameTab; SwitchToMode "Tab"; }
        }
        renamepane {
            bind "Ctrl c" { SwitchToMode "Normal"; }
            bind "Esc" { UndoRenamePane; SwitchToMode "Pane"; }
        }
        session {
            bind "Ctrl o" { SwitchToMode "Normal"; }
            bind "Ctrl s" { SwitchToMode "Scroll"; }
            bind "d" { Detach; }
        }
        tmux {
            bind "[" { SwitchToMode "Scroll"; }
            bind "Ctrl b" { Write 2; SwitchToMode "Normal"; }
            bind "\"" { NewPane "Down"; SwitchToMode "Normal"; }
            bind "%" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "z" { ToggleFocusFullscreen; SwitchToMode "Normal"; }
            bind "c" { NewTab; SwitchToMode "Normal"; }
            bind "," { SwitchToMode "RenameTab"; }
            bind "p" { GoToPreviousTab; SwitchToMode "Normal"; }
            bind "n" { GoToNextTab; SwitchToMode "Normal"; }
            bind "Left" { MoveFocus "Left"; SwitchToMode "Normal"; }
            bind "Right" { MoveFocus "Right"; SwitchToMode "Normal"; }
            bind "Down" { MoveFocus "Down"; SwitchToMode "Normal"; }
            bind "Up" { MoveFocus "Up"; SwitchToMode "Normal"; }
            bind "h" { MoveFocus "Left"; SwitchToMode "Normal"; }
            bind "l" { MoveFocus "Right"; SwitchToMode "Normal"; }
            bind "j" { MoveFocus "Down"; SwitchToMode "Normal"; }
            bind "k" { MoveFocus "Up"; SwitchToMode "Normal"; }
            bind "o" { FocusNextPane; }
            bind "d" { Detach; }
            bind "Space" { NextSwapLayout; }
            bind "x" { CloseFocus; SwitchToMode "Normal"; }
        }
        shared_except "locked" {
            bind "Ctrl g" { SwitchToMode "Locked"; }
            bind "Ctrl q" { Quit; }
            bind "Alt n" { NewPane; }
            bind "Alt h" "Alt Left" { MoveFocusOrTab "Left"; }
            bind "Alt l" "Alt Right" { MoveFocusOrTab "Right"; }
            bind "Alt j" "Alt Down" { MoveFocus "Down"; }
            bind "Alt k" "Alt Up" { MoveFocus "Up"; }
            bind "Alt =" "Alt +" { Resize "Increase"; }
            bind "Alt -" { Resize "Decrease"; }
            bind "Alt [" { PreviousSwapLayout; }
            bind "Alt ]" { NextSwapLayout; }
        }
        shared_except "normal" "locked" {
            bind "Enter" "Esc" { SwitchToMode "Normal"; }
        }
        shared_except "pane" "locked" {
            bind "Ctrl p" { SwitchToMode "Pane"; }
        }
        shared_except "resize" "locked" {
            bind "Ctrl n" { SwitchToMode "Resize"; }
        }
        shared_except "scroll" "locked" {
            bind "Ctrl s" { SwitchToMode "Scroll"; }
        }
        shared_except "session" "locked" {
            bind "Ctrl o" { SwitchToMode "Session"; }
        }
        shared_except "tab" "locked" {
            bind "Ctrl t" { SwitchToMode "Tab"; }
        }
        shared_except "move" "locked" {
            bind "Ctrl h" { SwitchToMode "Move"; }
        }
        shared_except "tmux" "locked" {
            bind "Ctrl b" { SwitchToMode "Tmux"; }
        }
    }


    // Choose the path to the default shell that zellij will use for opening new panes
    // Default: $SHELL
    //
    // default_shell "fish"


    // Toggle between having Zellij lay out panes according to a predefined set of layouts
    // whenever possible
    // Options:
    //   - true (default)
    //   - false
    //
    // auto_layout true

    // themes {
    //     dracula {
    //         fg 248 248 242
    //         bg 40 42 54
    //         red 255 85 85
    //         green 80 250 123
    //         yellow 241 250 140
    //         blue 98 114 164
    //         magenta 255 121 198
    //         orange 255 184 108
    //         cyan 139 233 253
    //         black 0 0 0
    //         white 255 255 255
    //     }
    // }
    mouse_mode true
    scroll_buffer_size 10000
    copy_on_select true
    pane_frames false
    // default_layout "compact"
    // layout_dir "/path/to/my/layout_dir"
    // theme_dir "/path/to/my/theme_dir"

    // Do not define to get OSC52 copying
    // copy_command "xclip -selection clipboard" // x11
    // copy_command "wl-copy"                    // wayland
    copy_command "pbcopy"                     // osx
    //copy_command "cb cp && movetomac"            // LINUX



  '';

  #home.file.".config/zellij/layouts/simple.kdl".text = ''
  #  layout {
  #      ${default_tab_template}
  #      tab
  #  }
  #'';
  #home.file.".config/zellij/layouts/default.kdl".text = ''
  #  layout {
  #      ${default_tab_template}
  #      tab name="music" {
  #        pane command="mpv" {
  #          args "https://raw.githubusercontent.com/junguler/m3u-radio-music-playlists/fc9e42a424451fbdfcc55920bb3af8b4c21531ac/web-radio_directory/90s.m3u"
  #        }
  #      }
  #      tab
  #  }
  #'';
}
