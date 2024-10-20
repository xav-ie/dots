{
  lib,
  pkgs,
  outputs,
  ...
}:
{
  imports = [ ../common ];

  config = {
    # darwin prefs and config items
    programs.zsh.enable = true;
    environment = {
      loginShell = pkgs.zsh;
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
        "/etc/profiles/per-user/x"
      ];
    };
    # unfortunately, this must be done in nix-darwin
    fonts.packages = with pkgs; [
      (nerdfonts.override {
        fonts = [
          # I like all these fonts a lot. You can test them by going to programmingfonts.org
          # However, the real names are to the right. I imagine it was renamed this way for
          # licensing reasons
          "FiraCode"
          "Hasklig"
          "JetBrainsMono"
          "Meslo"
          # also in general packages??
          "Monaspace" # "MonaspiceNe Nerd Font"
          # These ones should be in nerdfonts, but I guess they just aren't...
          # You can find them above in package installs :(
          # I think this is due to upstream not putting them in releases for some reason:
          # https://github.com/ryanoasis/nerd-fonts/releases/
          # "Cascadia Code"
          # "Maple"
          # "Martian Mono"
          # "MonoLisa"
          # "Twilio Sans Mono" # this one may be included in future release:
          # https://github.com/ryanoasis/nerd-fonts/pull/1465
        ];
      })
      maple-mono
      maple-mono-NF
      cascadia-code # "CaskaydiaCove Nerd Font"
      martian-mono
      # These two are not packaged at all:
      # "MonoLisa" # idk why this is not included yet in nerdfonts
      # "Twilio Sans Mono" # <== may change very soon, open pr to add it.
    ];
    # allow sudo to use touch id
    security.pam.enableSudoTouchIdAuth = true;
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
      };
      skhd = {
        enable = true;
        skhdConfig = # sh
          ''
            # I really like application driven window management. I just want
            # simple keybindings to just go where I want. Only downside is new
            # bindings must be added for new apps.
            ctrl - 1 : osascript -e 'tell application "wezterm" to activate'
            ctrl - 2 : osascript -e 'tell application "Firefox" to activate'
            ctrl - 3 : osascript -e 'tell application "Slack" to activate'
            ctrl - 4 : osascript -e 'tell application "zoom.us" to activate'
            ctrl - 5 : osascript -e 'tell application "Finder" to activate'
            ctrl - 6 : osascript -e 'tell application "Messages" to activate'
            ctrl - 7 : osascript -e 'tell application "Safari" to activate'
            ctrl + alt - 1 : osascript -e 'tell application "wezterm" to activate'
            ctrl + alt - 2 : osascript -e 'tell application "Firefox" to activate'
            ctrl + alt - 3 : osascript -e 'tell application "Slack" to activate'
            ctrl + alt - 4 : osascript -e 'tell application "zoom.us" to activate'
            ctrl + alt - 5 : osascript -e 'tell application "Finder" to activate'
            ctrl + alt - 6 : osascript -e 'tell application "Messages" to activate'
            ctrl + alt - 7 : osascript -e 'tell application "Safari" to activate'

            ctrl + alt - h : yabai -m space --focus prev
            ctrl + alt - j : yabai -m window --focus stack.next
            ctrl + alt - k : yabai -m window --focus stack.prev
            ctrl + alt - l : yabai -m space --focus next

            ctrl + alt - q : yabai -m window --space prev
            ctrl + alt - w : yabai -m space --focus prev
            ctrl + alt - e : yabai -m space --focus next
            ctrl + alt - r : yabai -m window --space next

            ctrl + alt - f : yabai -m window --toggle float;\
             yabai -m window --grid 4:4:1:1:2:2

            ctrl + alt - s : yabai -m window --toggle sticky;\
              yabai -m window --toggle topmost;\
              yabai -m window --toggle pip

            # sketchybar spacing, ensure windows do not overlap on monitors
            # without foreheads
            yabai -m config external_bar all:32:0
          '';
      };
    };

    # BECAUSE YA HAVE TO :/
    # https://github.com/nix-community/home-manager/issues/4026
    users.users.x.home = "/Users/x";

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

    nixpkgs = {
      overlays = builtins.attrValues outputs.overlays;
      # Allow unfree packages
      config.allowUnfree = true;
      # now you don't have to pass --impure when trying to run nix commands
      config.allowUnfreePredicate = _: true;
    };
  };
}
