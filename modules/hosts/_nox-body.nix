# nox (MacBook Air M3) host-specific configuration.
{
  lib,
  pkgs,
  config,
  fonts,
  ...
}:
let
  # Hash all user agents at build time to detect changes
  launchdUserAgentsHash =
    config.launchd.user.agents |> builtins.toJSON |> builtins.hashString "sha256";
in
{
  config = {
    networking.hostName = "nox";

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
        # Twingate = 1501592214;
        XCode = 497799835;
      };
      casks = [
        "android-studio"
        "blender"
        "chromium"
        "claude"
        "dockdoor"
        "ente"
        "figma"
        "firefox"
        "fluidvoice"
        "ghostty"
        "google-chrome"
        "loom"
        "microsoft-edge"
        "openvpn-connect"
        "protonvpn"
        "sf-symbols"
        "signal"
        "telegram"
        "transmission"
        "vlc"
        "vnc-viewer"
        "zoom"
        # "little-snitch"
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
    security.pam = {
      services.sudo_local = {
        enable = true;
        # fix mac os touch id in screen/tmux
        reattach = true;
        # allow sudo to use touch id
        touchIdAuth = true;
      };
    };

    # Grant TCC permissions to apps that fail to register properly
    # (common with Electron apps and some others)
    security.tcc = {
      enable = true;
      apps = [
        {
          bundleId = "org.whispersystems.signal-desktop";
          services = [
            "Camera"
            "Microphone"
            "ScreenCapture"
          ];
        }
        {
          bundleId = "org.mozilla.firefox";
          # Firefox's bundle is mutated in place (autoconfig injection in
          # home-darwin/firefox), which breaks its Apple seal — under
          # amfi_get_out_of_my_way=1 tccd then denies camera/mic/screen-capture.
          # home-darwin/firefox re-signs the bundle (user-level, for keychain access)
          # with whatever codesigning identity matches resignIdentity at runtime, and
          # we pin the bundle's resulting designated requirement. The coarse matcher
          # (not a pinned CN) means a rotated/renewed Apple Development cert just works
          # on the next `just system` — no config edit.
          appPath = "/Applications/Firefox.app";
          resignIdentity = "Apple Development";
          services = [
            "Camera"
            "Microphone"
            "ScreenCapture"
          ];
        }
        {
          # Chrome ships a proper Developer ID seal (Google LLC) and its bundle
          # isn't mutated, so a plain bundle-id grant is enough — no re-sign/csreq
          # pin like Firefox needs.
          bundleId = "com.google.Chrome";
          services = [
            "Camera"
            "Microphone"
            "ScreenCapture"
          ];
        }
        {
          bundleId = "us.zoom.xos";
          services = [
            "Camera"
            "Microphone"
            "ScreenCapture"
          ];
        }
        {
          bundleId = "com.brnbw.Tuna";
          services = [
            "Microphone"
            "SpeechRecognition"
          ];
        }
        {
          bundleId = "com.typewhisper.mac";
          services = [
            "Microphone"
            "Accessibility"
          ];
        }
        {
          # focusd (self-built AX daemon) is ad-hoc signed as com.x.focusd at build
          # time, so there's no cert to anchor a designated requirement — pin the
          # raw cdhash instead. Read it from the store bundle (not the ~/Applications
          # copy) so the grant doesn't depend on when the copy activation runs; the
          # copy preserves the seal, so its cdhash matches. The copy + agent kick
          # live in the focusd install snippet below.
          bundleId = "com.x.focusd";
          appPath = "${pkgs.pkgs-mine.focus-daemon}/Applications/focusd.app";
          pin = "cdhash";
          services = [ "Accessibility" ];
        }
      ];
    };

    launchd.user.agents.yabai.serviceConfig = {
      StandardOutPath = "/tmp/yabai_${config.defaultUser}.out.log";
      StandardErrorPath = "/tmp/yabai_${config.defaultUser}.err.log";
    };

    # Resident daemon behind the lcmd+<n> focus hotkeys. Tracks focus order via
    # AppKit (NSWorkspace) and activates via NSRunningApplication; per-window
    # cycling is done in-process through the Accessibility API, so switches are
    # ~native-fast and held keys coalesce instead of backlogging. AX is
    # Space-scoped, so the rare cross-desktop jump shells out to yabai (FOCUSD_YABAI)
    # for `space --focus` only — never on the hot path.
    #
    # Runs from the ~/Applications/focusd.app copy (installed + re-signed + granted
    # Accessibility by the activation block below), NOT the store binary, because
    # the notch move needs Accessibility pinned to that bundle's cdhash. FOCUSD_PKG
    # flips the launchd config hash so it restarts when focusd's code changes.
    launchd.user.agents.focusd.serviceConfig = {
      ProgramArguments = [
        "/Users/${config.defaultUser}/Applications/focusd.app/Contents/MacOS/focusd"
        "--daemon"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = {
        FOCUSD_YABAI = "${pkgs.yabai}/bin/yabai";
        FOCUSD_PKG = "${pkgs.pkgs-mine.focus-daemon}";
      };
      StandardOutPath = "/tmp/focusd.out.log";
      StandardErrorPath = "/tmp/focusd.err.log";
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
            # Direct path references - evaluated once
            # Thin client for the resident focus-daemon (launchd agent below);
            # sends the app name(s) over a unix socket and exits in ~1ms, so a
            # held key never backlogs.
            focus = "${pkgs.pkgs-mine.focus-daemon}/bin/focusd";
            move-pip = "${pkgs.pkgs-mine.move-pip}/bin/move-pip";
          in
          # sh
          ''
            # Application-driven window management - static list avoids imap1/concatStringsSep overhead
            lcmd - 1 : ${focus} Ghostty
            lcmd - 2 : ${focus} Firefox
            lcmd - 3 : ${focus} zoom.us
            lcmd - 4 : ${focus} Finder
            lcmd - 5 : ${focus} Messages Signal
            lcmd - 6 : ${focus} Chromium
            lcmd - 7 : ${focus} Safari

            ctrl + alt - h : yabai -m space --focus prev
            ctrl + alt - j : yabai -m window --focus stack.next
            ctrl + alt - k : yabai -m window --focus stack.prev
            ctrl + alt - l : yabai -m space --focus next

            cmd + alt - 1 : ${move-pip} top-left
            cmd + alt - 2 : ${move-pip} top-right
            cmd + alt - 3 : ${move-pip} bottom-right
            cmd + alt - 4 : ${move-pip} bottom-left
            cmd + alt - 5 : ${move-pip} top-middle
            cmd + alt - 6 : ${move-pip} middle-middle
            cmd + alt - 7 : ${move-pip} bottom-middle

            lcmd + alt - 0x1B : ${move-pip} shrink
            lcmd + alt - 0x18 : ${move-pip} grow

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
                      action="${firefoxWindowFocused}/bin/firefoxWindowFocused"
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
                        ^${firefoxExtensionWindowCreated}/bin/firefoxExtensionWindowCreated
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

            # Poke the focus-daemon on window create/destroy/move: it re-pins the
            # notch-held fullscreen window (yabai sees a fullscreen enter/exit as a
            # window create/destroy) and refreshes its cross-Space window cache so
            # lcmd+<n> can jump to a window on another desktop without a live query.
            yabai -m signal --add event=window_created label=focusd_recheck_c \
              action="${pkgs.pkgs-mine.focus-daemon}/bin/focusd --recheck-bar"
            yabai -m signal --add event=window_destroyed label=focusd_recheck_d \
              action="${pkgs.pkgs-mine.focus-daemon}/bin/focusd --recheck-bar"
            yabai -m signal --add event=window_moved label=focusd_recheck_m \
              action="${pkgs.pkgs-mine.focus-daemon}/bin/focusd --recheck-bar"
            # fix sketchybar bar not showing up on wake
            # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2409228441
            yabai -m signal --add event=system_woke \
              action="sh -c 'sleep 1; sketchybar --reload'"

            # Signal should not ever be full-width
            yabai -m rule --add app="^Signal$" \
              manage=off grid=1:3:2:0:1:1

            # Messages mirrors Signal's layout, pinned to the left third
            yabai -m rule --add app="^Messages$" \
              manage=off grid=1:3:0:0:1:1

            # Fix PiP not always floating
            yabai -m rule --add title="^Picture-in-Picture$" \
              sticky=on manage=off sub-layer=above

            # iPhone Mirroring: float as a PiP-style overlay
            yabai -m rule --add app="^iPhone Mirroring$" \
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

            # Center the Firefox profile launcher (more specific than above)
            yabai -m rule --add \
              app="^Firefox$" title="^Firefox - Choose a profile$" \
              manage=off sticky=on sub-layer=above grid=33:17:4:2:9:29
            # Auto re-open the Firefox window
            yabai -m signal --add event=window_created \
              app="^Firefox$" title="^(Firefox -.*|Extension:.*|.*Bitwarden)$" \
              action='${firefoxExtensionWindowCreated}/bin/firefoxExtensionWindowCreated'
            # sometimes, does not work... this seems to make up for it
            # TODO: test some more... probably not 100% there
            yabai -m signal --add event=window_title_changed \
              app="^Firefox$" title="^(Firefox -.*|Extension:.*|.*Bitwarden)$" \
              action='${logWindowPretty}/bin/logWindowPretty'
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
              ${checkSIP}/bin/checkSIP
            '';

        postActivation.text =
          lib.mkAfter # sh
            ''
              # Install focusd.app to ~/Applications (the notch move needs the daemon
              # running from a stable path). The store bundle is already ad-hoc signed
              # as com.x.focusd at build time, so we just copy it out — ditto preserves
              # the code seal, so the copy's cdhash matches what the Accessibility grant
              # pins. The grant itself lives in security.tcc.apps (pin = "cdhash", read
              # from the store bundle), which also kicks tccd. Marker-guarded: re-copies
              # only when focusd changes; the grant is idempotent and re-pins on its own.
              focusd_pkg="${pkgs.pkgs-mine.focus-daemon}"
              focusd_marker="/var/lib/nix-darwin/focusd-pkg"
              if [ "$(cat "$focusd_marker" 2>/dev/null)" != "$focusd_pkg" ]; then
                echo "🍃 Installing ~/Applications/focusd.app"
                focusd_uid=$(id -u ${config.defaultUser})
                focusd_app="/Users/${config.defaultUser}/Applications/focusd.app"
                sudo -u ${config.defaultUser} mkdir -p "/Users/${config.defaultUser}/Applications"
                sudo -u ${config.defaultUser} rm -rf "$focusd_app"
                sudo -u ${config.defaultUser} /usr/bin/ditto \
                  "$focusd_pkg/Applications/focusd.app" "$focusd_app"
                sudo -u ${config.defaultUser} chmod -R u+w "$focusd_app"
                sudo -u ${config.defaultUser} launchctl kickstart -k \
                  "gui/$focusd_uid/org.nixos.focusd" 2>/dev/null || true
                mkdir -p "$(dirname "$focusd_marker")"
                echo "$focusd_pkg" > "$focusd_marker"
              fi

              # Relaunch org.nixos user agents only if config changed
              hash_file="/var/lib/nix-darwin/launchd-user-agents.hash"
              current_hash="${launchdUserAgentsHash}"
              stored_hash=""
              [ -f "$hash_file" ] && stored_hash=$(cat "$hash_file")
              if [ "$current_hash" != "$stored_hash" ]; then
                for plist in /Users/${config.defaultUser}/Library/LaunchAgents/org.nixos.*.plist; do
                  [ -e "$plist" ] || continue
                  label=$(basename "$plist" .plist)
                  echo "🍃 Relaunching $label"
                  sudo -u ${config.defaultUser} launchctl kickstart -k "gui/$(id -u ${config.defaultUser})/$label" || true
                done
                mkdir -p "$(dirname "$hash_file")"
                echo "$current_hash" > "$hash_file"
              fi

              # https://github.com/koekeishiya/yabai/issues/2199#issuecomment-2031852290
              ${pkgs.yabai}/bin/yabai -m rule --apply 2>/dev/null || true

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

              ${config.boot-args.checkBootArgs}/bin/checkBootArgs

              # Activate user settings, sometimes takes a bit to fully apply
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
