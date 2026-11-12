{
  flake.modules.homeManager.darwin =
    {
      config,
      lib,
      pkgs,
      fonts,
      ...
    }:
    let
      # Single source of truth for the bar height. Consumed by
      # - `sketchybarrc.nu` via `(get_bar_height)` from nix-settings.nu
      # - the sketchybar-hover daemon via the SKETCHYBAR_BAR_HEIGHT env var,
      #   which sketchybarrc.nu sets from `(get_bar_height)` when starting it
      barHeight = "32";

      # so that I don't have to hard-code $HOME
      sketchybarWrapper = pkgs.writeShellScript "sketchybar-wrapper" ''
        exec ${pkgs.sketchybar}/bin/sketchybar --config "$HOME/.config/sketchybar/sketchybarrc" "$@"
      '';

      # TODO: get this to work
      # sketchybarReload = pkgs.writeShellScript "sketchybar-reload" ''
      #   # SDKROOT="$(xcrun --show-sdk-path)"
      #   swift ${./sketchybarReload.swift}
      # '';
    in
    {
      config = {
        home = {
          # sketchybar plus its helper binaries. The helpers are ALSO on the
          # launchd agent's PATH (below) — which is what the running bar uses —
          # but putting them on the interactive PATH too lets you invoke
          # `sketchybar` / plugins from a terminal without "sketchybar-hover:
          # command not found" spam.
          packages = [
            pkgs.pkgs-bleeding.sketchybar
            pkgs.pkgs-mine.sketchybar-hover
            pkgs.pkgs-mine.sketchybar-icons
            pkgs.pkgs-mine.sketchybar-battery
          ];
        };

        xdg.configFile = {
          "sketchybar/nix-settings.nu".text = # nu
            ''
              def get_label_font [] {
                "${fonts.configs.sketchybar.label-font}"
              }
              def get_app_font [] {
                "${fonts.configs.sketchybar.app-font}"
              }
              def get_bar_height [] {
                ${barHeight}
              }
            '';
          "sketchybar/sketchybarrc".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/sketchybarrc.nu";
          "sketchybar/open_volume_control.scpt".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/open_volume_control.scpt";
          "sketchybar/select_control_center.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/select_control_center.nu";
          "sketchybar/toggle_notification_center.js".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/toggle_notification_center.js";
          # Acceptance test for the bar's tiling invariant (no gaps/overlaps
          # between adjacent item footprints). Run:
          #   nu ~/.config/sketchybar/sb-check-tiling.nu
          "sketchybar/sb-check-tiling.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/sb-check-tiling.nu";

          "sketchybar/plugins/battery.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/battery.nu";
          "sketchybar/plugins/battery_icon.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/battery_icon.nu";
          "sketchybar/plugins/clock.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/clock.nu";
          "sketchybar/plugins/clock_icon.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/clock_icon.nu";
          "sketchybar/plugins/control_center.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/control_center.nu";
          "sketchybar/plugins/front_app.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/front_app.nu";
          "sketchybar/plugins/hidewin.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/hidewin.nu";
          "sketchybar/plugins/space.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/space.nu";
          "sketchybar/plugins/virtual_headset.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/virtual_headset.nu";
          "sketchybar/plugins/volume.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/volume.nu";
          "sketchybar/plugins/volume_icon.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/volume_icon.nu";
          "sketchybar/plugins/wifi.nu".source =
            config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/sketchybar/plugins/wifi.nu";
        };

        # Bind "Show Notification Center" (symbolic hotkey 163) to F19, a key no
        # keyboard here has, for toggle_notification_center.js: pressing the
        # clock's status item through accessibility closes Notification Center
        # again at once. Only this one entry is touched, so the rest of the
        # user's keyboard shortcuts stay as they are.
        home.activation.notificationCenterHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
          entry=":AppleSymbolicHotKeys:163"
          run /usr/libexec/PlistBuddy -c "Delete $entry" "$plist" 2>/dev/null || true
          run /usr/libexec/PlistBuddy \
            -c "Add $entry dict" \
            -c "Add $entry:enabled bool true" \
            -c "Add $entry:value dict" \
            -c "Add $entry:value:type string standard" \
            -c "Add $entry:value:parameters array" \
            -c "Add $entry:value:parameters:0 integer 65535" \
            -c "Add $entry:value:parameters:1 integer 80" \
            -c "Add $entry:value:parameters:2 integer 8388608" \
            "$plist"
          run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
        '';

        launchd.agents.sketchybar = {
          enable = true;
          config = {
            Debug = true;
            Program = sketchybarWrapper |> builtins.toString;
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/sketchybar.log";
            StandardErrorPath = "/tmp/sketchybar.err";
            StartInterval = 5;
            EnvironmentVariables.PATH = "${
              [
                pkgs.nushell
                pkgs.sketchybar
                pkgs.bash
                pkgs.pkgs-mine.sketchybar-hover
                # Renders the native Battery/Wi-Fi SF-Symbol PNGs used by the
                # battery_icon.nu / wifi.nu plugins (replaces the screen-recording
                # Control Center aliases).
                pkgs.pkgs-mine.sketchybar-icons
                # The `hidewin` item's click_script runs `screenshare-ui panel`.
                pkgs.pkgs-mine.screenshare-ui
                # The `virtual_headset` item's clicks run `virtual-headset panel|toggle-mute`.
                pkgs.pkgs-mine.virtual-headset
                # Control Center click_scripts skip the menu bar slide-down.
                pkgs.pkgs-mine.menubar-reveal
              ]
              |> lib.makeBinPath
            }:/usr/bin";
          };
        };

        # This agent listens through pmset, removing the need for a timer.
        launchd.agents.sketchybar-battery = {
          inherit (config.launchd.agents.sketchybar) enable;
          config = {
            Debug = true;
            Program = "${pkgs.pkgs-mine.sketchybar-battery}/bin/sketchybar-battery";
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/sketchybar-battery.log";
            StandardErrorPath = "/tmp/sketchybar-battery.err";
          };
        };

        # This agent listens through CoreWLAN events, so the Wi-Fi icon reacts
        # as fast as Control Center does, plus configd's network_change darwin
        # notification (which sketchybar can't receive itself) to catch hotspot
        # tether changes. It blocks on a run loop — no polling — and CoreWLAN
        # events only trigger when the *displayed* state changes, not on every
        # RSSI wobble.
        launchd.agents.sketchybar-wifi = {
          inherit (config.launchd.agents.sketchybar) enable;
          config = {
            Debug = true;
            ProgramArguments = [
              "${pkgs.pkgs-mine.sketchybar-icons}/bin/sketchybar-icons"
              "wifi"
              "--watch"
              "--trigger"
              "wifi_change"
            ];
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/sketchybar-wifi.log";
            StandardErrorPath = "/tmp/sketchybar-wifi.err";
            # --trigger shells out to `sketchybar` off PATH.
            EnvironmentVariables.PATH = "${lib.makeBinPath [ pkgs.sketchybar ]}:/usr/bin";
          };
        };

        # # reload sketchybar on screen off/on
        # # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2560079227
        # launchd.agents.sketchybarReload = {
        #   enable = true;
        #   config = {
        #     Debug = true;
        #     Program = "${sketchybarReload}";
        #     KeepAlive = true;
        #     RunAtLoad = true;
        #     StandardOutPath = "/tmp/sketchybarReload.log";
        #     StandardErrorPath = "/tmp/sketchybarReload.err";
        #   };
        # };
      };
    };
}
