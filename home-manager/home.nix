{ inputs, lib, config, pkgs, ... }: 
let 
  merge = lib.foldr (a: b: a // b) { };
  # see https://github.com/dj95/zjstatus
  default_tab_template = ''
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="file:${pkgs.zjstatus}/bin/zjstatus.wasm" {
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
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  # nixpkgs = {
  #   # You can add overlays here
  #   overlays = [
  #     # If you want to use overlays exported from other flakes:
  #     # neovim-nightly-overlay.overlays.default
  #
  #     # Or define it inline, for example:
  #     # (final: prev: {
  #     #   hi = final.hello.overrideAttrs (oldAttrs: {
  #     #     patches = [ ./change-hello-to-hi.patch ];
  #     #   });
  #     # })
  #   ];
  #   # Configure your nixpkgs instance
  #   config = {
  #     # Disable if you don't want unfree packages
  #     allowUnfree = true;
  #     # Workaround for https://github.com/nix-community/home-manager/issues/2942
  #     allowUnfreePredicate = (_: true);
  #   };
  # };

  # TODO: Set your username
  home = {
    username = "x";
    homeDirectory = "/home/x";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Enable home-manager and git
  programs = {
    home-manager = {
      enable = true;
      # useGlobalPkgs = true;

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
          true-color =  "always";
        };
        merge = {
          conflictstyle = "diff3";
        };
        diff = {
          colorMoved = "default";
        };
      };
    };
    zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableCompletion = true;
    };
    firefox = {
      enable = true;
      profiles.x = {
        id = 0;
        isDefault = true;
        settings = merge [
          (import ./programs/firefox/annoyances.nix)
          (import ./programs/firefox/settings.nix)

        ];
        userChrome = ''
          /* hides the native tabs */
          #TabsToolbar {
            visibility: collapse;
          }
          #titlebar {
            visibility: collapse;
          }
          #sidebar-header {
            visibility: collapse !important;
          } 
          '';
        extensions = with pkgs.nur.repos.rycee.firefox-addons; [
          bitwarden
          ublock-origin
          vimium-c
          sidebartabs
          newtab-adapter
          videospeed
        ];
      };
    };
    zellij = {
      enable = true;
      enableBashIntegration = true;
    };
  };

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

    // Choose what to do when zellij receives SIGTERM, SIGINT, SIGQUIT or SIGHUP
    // eg. when terminal window with an active zellij session is closed
    // Options:
    //   - detach (Default)
    //   - quit
    //
    // on_force_close "quit"

    //  Send a request for a simplified ui (without arrow fonts) to plugins
    //  Options:
    //    - true
    //    - false (Default)
    //
    // simplified_ui true

    // Choose the path to the default shell that zellij will use for opening new panes
    // Default: $SHELL
    //
    // default_shell "fish"

    // Choose the path to override cwd that zellij will use for opening new panes
    //
    // default_cwd ""

    // Toggle between having pane frames around the panes
    // Options:
    //   - true (default)
    //   - false
    //
    pane_frames false

    // Toggle between having Zellij lay out panes according to a predefined set of layouts 
    // whenever possible
    // Options:
    //   - true (default)
    //   - false
    //
    // auto_layout true

    // Define color themes for Zellij
    // For more examples, see: https://github.com/zellij-org/zellij/tree/main/example/themes
    // Once these themes are defined, one of them should to be selected in the "theme"
    // section of this file
    //
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

    // Choose the theme that is specified in the themes section.
    // Default: default
    //
    // theme "default"

    // The name of the default layout to load on startup
    // Default: "default"
    //
    // default_layout "compact"

    // Choose the mode that zellij uses when starting up.
    // Default: normal
    //
    // default_mode "locked"

    // Toggle enabling the mouse mode.
    // On certain configurations, or terminals this could
    // potentially interfere with copying text.
    // Options:
    //   - true (default)
    //   - false
    //
    // mouse_mode false

    // Configure the scroll back buffer size
    // This is the number of lines zellij stores for each pane in the scroll back
    // buffer. Excess number of lines are discarded in a FIFO fashion.
    // Valid values: positive integers
    // Default value: 10000
    //
    // scroll_buffer_size 10000

    // Provide a command to execute when copying text. The text will be piped to
    // the stdin of the program to perform the copy. This can be used with
    // terminal emulators which do not support the OSC 52 ANSI control sequence
    // that will be used by default if this option is not set.
    // Examples:
    //
    // copy_command "xclip -selection clipboard" // x11
    // copy_command "wl-copy"                    // wayland
    // copy_command "pbcopy"                     // osx
    copy_command "cb cp && movetomac"            // LINUX


    // Choose the destination for copied text
    // Allows using the primary selection buffer (on x11/wayland) instead of the system clipboard.
    // Does not apply when using copy_command.
    // Options:
    //   - system (default)
    //   - primary
    //
    // copy_clipboard "primary"

    // Enable or disable automatic copy (and clear) of selection when releasing mouse
    // Default: true
    //
    // copy_on_select false

    // Path to the default editor to use to edit pane scrollbuffer
    // Default: $EDITOR or $VISUAL
    //
    // scrollback_editor "/usr/bin/vim"

    // When attaching to an existing session with other users,
    // should the session be mirrored (true)
    // or should each user have their own cursor (false)
    // Default: false
    //
    // mirror_session true

    // The folder in which Zellij will look for layouts
    //
    // layout_dir "/path/to/my/layout_dir"

    // The folder in which Zellij will look for themes
    //
    // theme_dir "/path/to/my/theme_dir"
  '';

  home.file.".config/zellij/layouts/simple.kdl".text = ''
    layout {
        ${default_tab_template}
        tab
    }
  '';
  home.file.".config/zellij/layouts/default.kdl".text = ''
    layout {
        ${default_tab_template}
        tab name="music" {
          pane command="mpv" {
            args "https://raw.githubusercontent.com/junguler/m3u-radio-music-playlists/fc9e42a424451fbdfcc55920bb3af8b4c21531ac/web-radio_directory/90s.m3u"
          }
        }
        tab name="slack" {
          pane command="weechat"
        }
        tab name="mail" {
          pane command="nvim" {
            args "+Himalaya Work"
          }
        }
        tab name="gh dash" {
          pane command="gh" {
            args "dash"
          }
        }
        tab
    }
  '';

  gtk = {
    enable = true;
    theme.name = "adw-gtk3";
    cursorTheme.name = "Bibata-Modern-Ice";
    iconTheme.name = "GruvboxPlus";
  };


  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "qutebrowser.desktop" ];
    "application/pdf" = [ "sioyek.desktop" ];
    "image/*" = [ "sxiv.desktop" ];
    "video/*" = [ "mpv.desktop" ];
    "text/html" = [ "qutebrowser.desktop" ];
    "x-scheme-handler/http" = [ "qutebrowser.desktop" ];
    "x-scheme-handler/https" = [ "qutebrowser.desktop" ];
    "x-scheme-handler/ftp" = [ "qutebrowser.desktop" ];
    "application/xhtml+xml" = [ "qutebrowser.desktop" ];
    "application/xml" = [ "qutebrowser.desktop" ]; 
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
  home.sessionVariables = {
    EDITOR = "nvim";
  };
}


