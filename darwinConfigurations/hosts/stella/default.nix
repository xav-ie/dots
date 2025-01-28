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
    # TODO: mas recently got uninstall working, adjust these steps

    # 1. what is currently installed?
    # ❯ mas list | awk '{print $1}'
    # 682658836
    # 408981434
    # 1501592214 # twingate
    # 409201541
    # 409183694
    # 6446206067 # klack
    # 409203825
    #
    # 2. By tacking on the mas apps that should be installed, we can filter with
    # `uniq -u` and get the ones that should *not* be installed like this:
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u
    # 408981434
    # 409183694
    # 409201541
    # 409203825
    # 682658836
    #
    # 3. a. `sudo mas uninstall` each id
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {} sudo mas uninstall {}
    # Error: Not installed # x5
    # whoops! https://github.com/mas-cli/mas/issues/313
    # `mas` should be able to uninstall but it looks like there is some intricate
    # permissions issues
    #
    # 3. b. workaround using manual method
    # Get the bundleId of each of the applications to uninstall
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId'
    # com.apple.iMovieApp
    # com.apple.iWork.Keynote
    # com.apple.iWork.Pages
    # com.apple.iWork.Numbers
    # com.apple.garageband10
    #
    # 4. Use these bundleIds returns to look up their location on the computer
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId' \
    #   | xargs -I {} mdfind "kMDItemCFBundleIdentifier == '{}'"
    # /Applications/iMovie.app
    # /Applications/Keynote.app
    # /Applications/Pages.app
    # /Applications/Numbers.app
    # /Applications/GarageBand.app
    # ^ the benefit of using `mdfind` is that is sidesteps the issue in `mas`
    # as it only searches locations available to the current user. This means,
    # as long as permissions are set up correctly so that *you* cannot see
    # another user's home directory, then their `~/Applications/` will never
    # show up here! We could also apply filtering here to be extra safe, but
    # uncessary. Especially so since I don't plan on having multiple users ever.
    # Oooooof. But if you have a Cask installed with `brew`, that would also show
    # up in this list. I don't use `brew`, but you would need to somehow query
    # its install locations and exclude those from this list, since those could
    # not have been made by mas.
    #
    # 5. uninstall 🎉
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId' \
    #   | xargs -I {} mdfind "kMDItemCFBundleIdentifier == '{}'" \
    #   | xargs -I {} sudo rm -rf {}
    #
    # 6. Bonus: use GNU Parallel to increase uninstall speed
    # having to download each, then parse each, then remove each sequentially
    # is slow and unnecessary. Using GNU Parallel, we can greatly increase the
    # speed of this to be nearly instantaneous.
    #
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214" ) | sort | uniq -u \
    #   | parallel -j $(nproc) '
    #   # Fetch the bundleId using iTunes API
    #   bundleId=$(curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #            | jq -r ".results[0].bundleId");
    #
    #   # Find the application path using mdfind
    #   appPath=$(mdfind "kMDItemCFBundleIdentifier == \"$bundleId\"");
    #
    #   # Uninstall the app if found
    #   if [ -n "$appPath" ]; then
    #     echo "Uninstalling $appPath...";
    #     sudo rm -rf "$appPath";
    #
    #     # Optionally clean up support files
    #     sudo rm -rf ~/Library/Preferences/"$bundleId".plist;
    #     sudo rm -rf ~/Library/Caches/"$bundleId";
    #     sudo rm -rf ~/Library/Application\ Support/"$bundleId";
    #   else
    #     echo "App not found for ID {}";
    #   fi
    # '
    #
    # # Apps to install/keep:
    # 6446206067 # klack
    # 1501592214 # twingate
    # 497799835 # xcode

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
        # I think this is due to upstream not putting them in releases for some reason:
        # https://github.com/ryanoasis/nerd-fonts/releases/
        # "Cascadia Code"
        # "Maple"
        # "Martian Mono"
        # "MonoLisa"
        # "Twilio Sans Mono" # this one may be included in future release:
        # https://github.com/ryanoasis/nerd-fonts/pull/1465
      ]);
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
        extraConfig = # sh
          ''
            yabai -m rule --add app=".*" sub-layer=normal
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
        skhdConfig = # sh
          ''
            # I really like application driven window management. I just want
            # simple keybindings to just go where I want. Only downside is new
            # bindings must be added for new apps.
            cmd - 1 : osascript -e 'tell application "Ghostty" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Ghostty"
            cmd - 2 : osascript -e 'tell application "Firefox" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Firefox"
            cmd - 3 : osascript -e 'tell application "Slack" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Slack"
            cmd - 4 : osascript -e 'tell application "zoom.us" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="zoom.us"
            cmd - 5 : osascript -e 'tell application "Finder" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Finder"
            cmd - 6 : osascript -e 'tell application "Messages" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Messages"
            cmd - 7 : osascript -e 'tell application "Chromium" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Chromium"
            cmd - 8 : osascript -e 'tell application "Safari" to activate' \
             && sketchybar --update \
             && sketchybar --set "front_app" label="Safari"

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
