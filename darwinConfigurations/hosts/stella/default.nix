{
  lib,
  pkgs,
  user,
  ...
}:
{
  config = {
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
        Klack = 6446206067;
        Twingate = 1501592214;
        XCode = 497799835;
      };
      casks = [
        "android-studio"
        "bitwarden"
        "chromium"
        "ente"
        "firefox"
        "ghostty"
        "little-snitch"
        "loom"
        "microsoft-edge"
        "openvpn-connect"
        "protonvpn"
        "raycast"
        "sf-symbols"
        "slack"
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
        "/etc/profiles/per-user/${user}"
      ];
    };
    # unfortunately, this must be done in nix-darwin
    fonts.packages =
      (with pkgs; [
        maple-mono
        maple-mono-NF
        # These two are not packaged at all:
        # "MonoLisa" # idk why this is not included yet in nerdfonts
        # "Twilio Sans Mono" # <== may change very soon, open pr to add it.
      ])
      ++ (with pkgs.nerd-fonts; [
        # I like all these fonts a lot. You can test them by going to programmingfonts.org
        # However, the real names are to the right. I imagine it was renamed this way for
        # licensing reasons
        caskaydia-cove # "CaskaydiaCove Nerd Font"
        fira-code
        hasklug
        jetbrains-mono
        martian-mono
        meslo-lg
        # also in general packages??
        monaspace # "MonaspiceNe Nerd Font"
        # These ones should be in nerdfonts, but I guess they just aren't...
        # You can find them above in package installs :(
        # I think this is due to upstream not putting them in releases for some
        # reason:
        # https://github.com/ryanoasis/nerd-fonts/releases/
        # "Cascadia Code"
        # "Maple"
        # "Martian Mono"
        # "MonoLisa"
        # "Twilio Sans Mono" # this one may be included in future release:
        # https://github.com/ryanoasis/nerd-fonts/pull/1465
      ]);
    security.pam = {
      # fix mac os touch id in screen/tmux
      enablePamReattach = true;
      # allow sudo to use touch id
      enableSudoTouchIdAuth = true;
    };
    services = {
      nix-daemon.enable = true;
      # a lot of this is taken from https://github.com/shaunsingh/nix-darwin-dotfiles/commit/a457a0b2d0e68d810e3503f84217db8698dd9533
      yabai = {
        enable = true;
        enableScriptingAddition = true;
        config =
          let
            spacing = 0;
          in
          {
            focus_follows_mouse = "autoraise";
            mouse_follows_focus = "off";
            mouse_drop_action = "stack";
            window_placement = "second_child";
            window_opacity = "off";
            window_topmost = "on";
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
        extraConfig = # sh
          ''
            yabai -m rule --add app=".*" sub-layer=normal
            # Fix PiP not always floating
            yabai -m rule --add title="^Picture-in-Picture$" sticky=on manage=off sub-layer=above
            # sketchybar spacing, ensure windows do not overlap on monitors
            # without foreheads
            yabai -m config external_bar all:32:0
            # fix sketchybar bar not showing up on wake
            # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2409228441
            yabai -m signal --add event=system_woke action="sh -c 'sleep 1; sketchybar --reload'"
          '';
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
            commands = lib.lists.imap1 (
              index: elem: # sh
              ''
                cmd - ${builtins.toString index}: osascript -e 'tell application "${elem}" to activate'
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
    };

    # BECAUSE YA HAVE TO :/
    # https://github.com/nix-community/home-manager/issues/4026
    users.users."${user}".home = "/Users/${user}";

    system = {
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
                LSHandlerRoleAll = "com.tinyspeck.slackmacgap";
                LSHandlerURLScheme = "slack";
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
          "com.raycast.macos" = {
            useHyperKeyIcon = true;
            onboardingCompleted = true;
            "NSStatusItem Visible raycastIcon" = false;
            "emojiPicker_skinTone" = "standard";
            raycastCurrentThemeId = "bundled-raycast-dark";
            raycastCurrentThemeIdDarkAppearance = "bundled-raycast-dark";
            raycastCurrentThemeIdLightAppearance = "bundled-raycast-light";
            raycastShouldFollowSystemAppearance = 1;
            showGettingStartedLink = 0;
            navigationCommandStyleIdentifierKey = "vim";
          };

        };
      };

      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToEscape = true;
      };

      stateVersion = 5;
    };

  };
}
