{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
in
{
  imports = [
    ../../modules
  ];

  config = {
    # https://github.com/nix-darwin/nix-darwin/issues/1035
    # seems to be waiting on
    # https://github.com/nix-darwin/nix-darwin/pull/1205
    # networking.hosts = { };
    # For now, we must manually edit :/

    homebrew = {
      enable = true;
      # do not prompt for updates
      caskArgs.no_quarantine = true;
      # track brews in a file
      global.brewfile = true;
      onActivation = {
        # destroy app config and app on removal from nix-darwin
        cleanup = "zap";
      };
      masApps = {
        Bitwarden = 1352778147;
        Klack = 6446206067;
        Tailscale = 1475387142;
        Twingate = 1501592214;
        XCode = 497799835;
      };
      casks = [
        "android-studio"
        "chromium"
        "ente"
        "firefox"
        "ghostty"
        "google-chrome"
        # "little-snitch"
        "loom"
        "microsoft-edge"
        "openvpn-connect"
        "protonvpn"
        "sf-symbols"
        "signal"
        "transmission"
        "vlc"
        "vnc-viewer"
        "zoom"
      ];
      brews = [ "mas" ];
    };

    # darwin prefs and config items
    programs.zsh.enable = true;
    environment = {
      shells = [
        pkgs.bash
        pkgs.zsh
      ];
      systemPackages = with pkgs; [ coreutils ];
      pathsToLink = [ "/Applications" ];
      # use the version of nix that is from nix-darwin and home-manager and
      # disable using /nix/var/nix/profiles/default and ~/.nixprofile
      profiles = lib.mkForce [
        "/run/current-system/sw"
        "/etc/profiles/per-user/${config.defaultUser}"
      ];
    };
    fonts.packages = fonts.packages;
    # unfortunately, this must be done in nix-darwin
    # fonts.packages =
    #   (with pkgs; [
    #     maple-mono.truetype-autohint
    #     maple-mono.NF
    #     # These two are not packaged at all:
    #     # "MonoLisa" # idk why this is not included yet in nerdfonts
    #     # "Twilio Sans Mono" # <== may change very soon, open pr to add it.
    #   ])
    #   ++ (with pkgs.nerd-fonts; [
    #     # I like all these fonts a lot. You can test them by going to programmingfonts.org
    #     # However, the real names are to the right. I imagine it was renamed this way for
    #     # licensing reasons
    #     caskaydia-cove # "CaskaydiaCove Nerd Font"
    #     fira-code
    #     hasklug
    #     jetbrains-mono
    #     martian-mono
    #     meslo-lg
    #     # also in general packages??
    #     monaspace # "MonaspiceNe Nerd Font"
    #     # These ones should be in nerdfonts, but I guess they just aren't...
    #     # You can find them above in package installs :(
    #     # I think this is due to upstream not putting them in releases for some
    #     # reason:
    #     # https://github.com/ryanoasis/nerd-fonts/releases/
    #     # "Cascadia Code"
    #     # "Maple"
    #     # "Martian Mono"
    #     # "MonoLisa"
    #     # "Twilio Sans Mono" # this one may be included in future release:
    #     # https://github.com/ryanoasis/nerd-fonts/pull/1465
    #   ]);
    security.pam = {
      services.sudo_local = {
        enable = true;
        # fix mac os touch id in screen/tmux
        reattach = true;
        # allow sudo to use touch id
        touchIdAuth = true;
      };
    };

    launchd.user.agents.yabai.serviceConfig = {
      StandardOutPath = "/tmp/yabai_${config.defaultUser}.out.log";
      StandardErrorPath = "/tmp/yabai_${config.defaultUser}.err.log";
    };

    services = {
      openssh = {
        enable = true;
        settings = {
          AcceptEnv = "COLORTERM TERM LANG LC_ALL TESTING";
        };
      };
      skhd = {
        enable = true;
        skhdConfig =
          let
            applications = [
              "Ghostty"
              "Firefox"
              "zoom.us"
              "Finder"
              "Messages"
              "Chromium"
              "Safari"
            ];
            focus-or-open-application = lib.getExe pkgs.pkgs-mine.focus-or-open-application;
            commands = lib.lists.imap1 (
              index: elem: # sh
              ''
                cmd - ${builtins.toString index}: ${focus-or-open-application} ${elem}
              '') applications;
            commandString = builtins.concatStringsSep "\n" commands;
            move-pip = lib.getExe pkgs.pkgs-mine.move-pip;
          in
          # sh
          ''
            # I really like application-driven window management. I just want
            # simple keybindings to just go where I want. Only downside is new
            # bindings must be added for new apps.
            ${commandString}

            ctrl + alt - h : yabai -m space --focus prev
            ctrl + alt - j : yabai -m window --focus stack.next
            ctrl + alt - k : yabai -m window --focus stack.prev
            ctrl + alt - l : yabai -m space --focus next

            cmd + alt - 1 : ${move-pip} top-left
            cmd + alt - 2 : ${move-pip} top-right
            cmd + alt - 3 : ${move-pip} bottom-right
            cmd + alt - 4 : ${move-pip} bottom-left

            ctrl + alt - q : yabai -m window --space prev
            ctrl + alt - w : yabai -m space --focus prev
            ctrl + alt - e : yabai -m space --focus next
            ctrl + alt - r : yabai -m window --space next

            ctrl + alt - f : yabai -m window --toggle float;\
             yabai -m window --grid 4:4:1:1:2:2

            ctrl + alt - s : yabai -m window --toggle sticky;\
              yabai -m window --toggle topmost;\
              yabai -m window --toggle pip
          '';
      };
      # a lot of this is taken from https://github.com/shaunsingh/nix-darwin-dotfiles/commit/a457a0b2d0e68d810e3503f84217db8698dd9533
      yabai = {
        enable = true;
        enableScriptingAddition = true;
        config =
          let
            spacing = 0;
          in
          {
            # debug_output = "on";
            focus_follows_mouse = "autoraise";
            mouse_follows_focus = "off";
            mouse_drop_action = "stack";
            window_placement = "second_child";
            window_opacity = "off";
            window_shadow = "off";
            active_window_opacity = "1.0";
            normal_window_opacity = "1.0";
            split_ratio = "0.50";
            auto_balance = "on";
            mouse_modifier = "fn";
            mouse_action1 = "move";
            mouse_action2 = "resize";
            layout = "stack";
            top_padding = spacing;
            bottom_padding = spacing;
            left_padding = spacing;
            right_padding = spacing;
            window_gap = spacing;
          };
        extraConfig =
          let
            oneShotName = "window_focused_firefox_oneshot";
            get_window = # nu
              ''
                def get_window [] {
                  (yabai -m query --windows
                    --window $env.YABAI_WINDOW_ID | complete | get stdout
                    | from json)
                }
              '';
            firefoxWindowFocused = pkgs.writeNuApplication {
              name = "firefoxWindowFocused";
              runtimeInputs = [
                pkgs.skhd
                pkgs.yabai
              ];
              text = # nu
                ''
                  ${get_window}
                  def main [] {
                    let current_window = (get_window)
                    if ($current_window.title | str starts-with "Extension:") {
                      return;
                    }
                    try {
                      yabai -m signal --remove ${oneShotName}
                      skhd -k "cmd + shift - y"
                    }

                  }
                '';
            };
            # re-opens the bitwarden extension app on firefox
            firefoxExtensionWindowCreated = pkgs.writeNuApplication {
              name = "firefoxExtensionWindowCreated";
              runtimeInputs = [ pkgs.yabai ];
              text = # nu
                ''
                  def main [] {
                    (yabai -m signal --add event=window_focused
                      app="^Firefox$"
                      action="${lib.getExe firefoxWindowFocused}"
                      label="${oneShotName}")
                  }
                '';
            };
            logWindowPretty = pkgs.writeNuApplication {
              name = "logWindowPretty";
              runtimeInputs = [
                pkgs.yabai
              ];
              text = # nu
                ''
                  ${get_window}
                  def main [] {
                    let current_window = (get_window)
                    if (not $current_window.is-floating) {
                      if ($current_window.title | str starts-with "Extension:") {
                        print (date now)
                        print $current_window.title
                        (yabai -m window $env.YABAI_WINDOW_ID
                          --toggle float)
                        (yabai -m window $env.YABAI_WINDOW_ID
                          --grid 5:4:3:1:1:3)
                        ^${lib.getExe firefoxExtensionWindowCreated}
                      }
                    }
                  }
                '';
            };
          in
          # sh
          ''
            yabai -m rule --add app=".*" \
              sub-layer=normal

            # sketchybar spacing, ensure windows do not overlap on monitors
            # without foreheads
            yabai -m config external_bar all:32:0
            # fix sketchybar bar not showing up on wake
            # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2409228441
            yabai -m signal --add event=system_woke \
              action="sh -c 'sleep 1; sketchybar --reload'"

            # Signal should not ever be full-width
            yabai -m rule --add app="^Signal$" \
              manage=off grid=1:3:2:0:1:1

            # Fix PiP not always floating
            yabai -m rule --add title="^Picture-in-Picture$" \
              sticky=on manage=off sub-layer=above

            # Do not resize Safari "Web Inspector.*" windows
            yabai -m rule --add title="^Web Inspector.*" \
              manage=off
            # Do not resize Firefox Browser Toolbox windows
            yabai -m rule --add app="^Firefox$" title=".*Browser Toolbox$" \
              manage=off

            # Do not manage Firefox extension popups newly created and spawn in
            # good place
            yabai -m rule --add \
              app="^Firefox$" title="^(Firefox -.*|Extension:.*|.*Bitwarden)$" \
              manage=off sticky=on sub-layer=above grid=5:4:3:1:1:3
            # Auto re-open the Firefox window
            yabai -m signal --add event=window_created \
              app="^Firefox$" title="^(Firefox -.*|Extension:.*|.*Bitwarden)$" \
              action='${lib.getExe firefoxExtensionWindowCreated}'
            # sometimes, does not work... this seems to make up for it
            # TODO: test some more... probably not 100% there
            yabai -m signal --add event=window_title_changed \
              app="^Firefox$" title="^(Firefox -.*|Extension:.*|.*Bitwarden)$" \
              action='${lib.getExe logWindowPretty}'
          '';
      };
    };

    # BECAUSE YA HAVE TO :/
    # https://github.com/nix-community/home-manager/issues/4026
    users.users."${config.defaultUser}".home = "/Users/${config.defaultUser}";

    system = {
      activationScripts = {
        preActivation.text =
          let
            checkSIP = pkgs.writeNuApplication {
              name = "checkSIP";
              text = # nu
                ''
                  def main [] {
                    let result = (csrutil status | complete | get stdout)
                    if ($result | str contains "enabled") {
                      print -e $"(ansi red)  Please disable SIP, first. See:(ansi reset)"
                      let link_text = "https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection"
                      print -e $"(ansi cyan)($link_text | ansi link)(ansi reset)"
                      exit 1
                    }
                  }
                '';
            };
          in
          lib.mkAfter # sh
            ''
              ${lib.getExe checkSIP}
            '';

        postActivation.text =
          lib.mkAfter # sh
            ''
              # Relaunch org.nixos user agents to pick up new paths
              for plist in /Users/${config.defaultUser}/Library/LaunchAgents/org.nixos.*.plist; do
                [ -e "$plist" ] || continue
                label=$(basename "$plist" .plist)
                echo "🍃 Relaunching $label"
                sudo -u ${config.defaultUser} launchctl kickstart -k "gui/$(id -u ${config.defaultUser})/$label" || true
              done

              # https://github.com/koekeishiya/yabai/issues/2199#issuecomment-2031852290
              ${lib.getExe pkgs.yabai} -m rule --apply 2>/dev/null || true

              # Power management for remote builder
              # Battery: aggressive sleep for battery life
              # AC: longer sleep (3 hours) for remote builds
              pmset -b sleep 1   # Battery: sleep after 1 min
              pmset -c sleep 180 # AC: sleep after 3 hours

              # Enable wake for network access (SSH wake via HomePod sleep proxy)
              # ttyskeepawake: keep system awake when SSH/tty sessions are active
              # womp: wake on magic packet (wake for network access)
              pmset -a ttyskeepawake 1
              pmset -a womp 1

              ${lib.getExe config.boot-args.checkBootArgs}

              # Activate user settings, somethimes takes a bit to fully apply
              sudo -u ${config.defaultUser} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
            '';
      };

      defaults = {
        dock = {
          autohide = true;
          autohide-delay = 0.0;
          show-recents = false;
          static-only = true;
          wvous-tl-corner = 2;
          wvous-tr-corner = 1;
          wvous-br-corner = 1;
          wvous-bl-corner = 1;
        };
        finder = {
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          QuitMenuItem = true;
          ShowPathbar = true;
          ShowStatusBar = true;
          _FXShowPosixPathInTitle = true;
        };
        NSGlobalDomain = {
          # automatically hide the menu bar
          _HIHideMenuBar = true;

          InitialKeyRepeat = 14;
          KeyRepeat = 1;
        };
        screencapture.disable-shadow = true;
        trackpad = {
          Clicking = true;
          Dragging = true;
        };

        CustomUserPreferences = {
          "com.apple.AppleMultitouchTrackpad" = {
            Clicking = true;
            HIDScrollZoomModifierMask = 262144; # Control key for zoom
          };
          "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
            Clicking = true;
          };
          "com.apple.universalaccess" = {
            closeViewScrollWheelToggle = true;
          };
          "com.apple.AdLib" = {
            allowApplePersonalizedAdvertising = 0;
            allowIdentifierForAdvertising = 0;
          };
          # default application settings
          # TODO: setup a read check first, check if different, then prompt if
          # you would like to update...
          # This currently forcefully resets the default applications on every
          # darwin switch :/
          "com.apple.LaunchServices/com.apple.launchservices.secure" = {
            LSHandlers = [
              {
                LSHandlerPreferredVersions = {
                  LSHandlerRoleAll = "-";
                };
                LSHandlerRoleAll = "com.bitwarden.desktop";
                LSHandlerURLScheme = "bitwarden";
              }
              {
                LSHandlerPreferredVersions = {
                  LSHandlerRoleAll = "-";
                };
                LSHandlerRoleAll = "org.mozilla.firefox";
                LSHandlerURLScheme = "http";
              }
              {
                LSHandlerPreferredVersions = {
                  LSHandlerRoleAll = "-";
                };
                LSHandlerRoleAll = "org.mozilla.firefox";
                LSHandlerURLScheme = "https";
              }
              {
                LSHandlerContentType = "public.html";
                LSHandlerPreferredVersions = {
                  LSHandlerRoleAll = "-";
                };
                LSHandlerRoleAll = "org.mozilla.firefox";
              }
            ];
          };
        };
      };

      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToEscape = true;
      };

      primaryUser = config.defaultUser;

      stateVersion = 5;
    };

  };
}
