# hide-windows: inject screenshare-ui's per-app hiding library
# (ScreenshareUIHideWindows.dylib, from inputs.screenshare-ui) into every GUI
# app. Windows are VISIBLE by default (so continuous recorders like Dayflow
# work); screenshare-ui's Screenshare Mode hides everything from capture for a
# meeting, and you reveal the apps you want to present.
#
# An NSWindow is excluded from window-level capture (ScreenCaptureKit,
# CGWindowListCreateImage, all browser getDisplayMedia sharing incl.
# Zoom-in-a-tab) when its sharingType is NSWindowSharingNone — but that
# flag only works when set by the process that OWNS the window. So the library
# rides the shared services.dyldInject.libraries inject to run inside every GUI
# process and flips the flag from the inside (mechanism and ceiling:
# hide-windows/HideWindows.m in screenshare-ui; native Zoom's default
# display-buffer capture bypasses it; browser sharing honors it).
#
# The sharing flag is per-window, honored by ALL window-level capturers —
# there's no "hide from Meet but show to Dayflow" exception. That's why
# hiding is a mode you toggle for a meeting, not an always-on filter.
#
# Required system state (assumed, set elsewhere): SIP disabled +
# amfi_get_out_of_my_way=1 (../boot-args.nix) — without amfi off, dyld
# strips DYLD_INSERT_LIBRARIES from hardened-runtime apps and the dylib
# never loads.
#
# Enabled by default. To opt out:  services.dyldInject.hideWindows.enable = false;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.hideWindows;
  hide-windows = pkgs.pkgs-mine.screenshare-ui-hide-windows;
in
{
  options.services.dyldInject.hideWindows = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Inject a dylib into every GUI app that can flip its windows to
        NSWindowSharingNone (excluded from screen capture). Windows are
        visible by default; screenshare-ui's Screenshare Mode hides them
        for a meeting, and you reveal apps to present.
      '';
    };

    grantScreenCaptureToAllApps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Grant Screen Recording to every installed app at activation. On
        macOS 26, an app WITHOUT Screen Recording can hide a window from
        capture only once: after the window has been made capturable again,
        the WindowServer ignores every later NSWindowSharingNone from that
        app (AppKit, raw CGSSetWindowSharingState, re-showing with either
        value, rebuilding the server window: all refused; only a relaunch
        resets it). Apps WITH the permission toggle normally (verified with
        the same test app, in real captures). So a second Screenshare Mode in
        one session would leak every such app. The cost: any app can record
        the screen without asking (the menu-bar recording indicator still
        shows). Covers apps installed at activation time; one installed later
        is covered at the next rebuild.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.dyldInject.libraries = [
      "${hide-windows}/lib/ScreenshareUIHideWindows.dylib"
    ];

    # Grants only what's missing (one DB read), so a rebuild costs nothing once
    # everything is covered. Bundle-id grants, no code-requirement pin: they
    # must keep matching across app updates and re-signs.
    system.activationScripts.postActivation.text = lib.mkIf cfg.grantScreenCaptureToAllApps (
      lib.mkAfter ''
        echo "Granting Screen Recording to installed apps (hide-windows)..."
        sc_db="/Library/Application Support/com.apple.TCC/TCC.db"
        sc_have=$(/usr/bin/sqlite3 "$sc_db" \
          "SELECT client FROM access WHERE service='kTCCServiceScreenCapture' AND client_type=0 AND auth_value=2;")
        sc_granted=0
        for sc_app in /Applications/*.app /Applications/*/*.app \
          "/Users/${config.defaultUser}"/Applications/*.app \
          /System/Applications/*.app /System/Applications/Utilities/*.app \
          /System/Library/CoreServices/Finder.app; do
          [ -f "$sc_app/Contents/Info.plist" ] || continue
          sc_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$sc_app/Contents/Info.plist" 2>/dev/null) || continue
          [ -n "$sc_id" ] || continue
          printf '%s\n' "$sc_have" | /usr/bin/grep -qxF "$sc_id" && continue
          ${lib.getExe config.security.tcc.package} --service ScreenCapture \
            --bundle-id "$sc_id" --db "$sc_db" >/dev/null && sc_granted=$((sc_granted + 1))
          sc_have=$(printf '%s\n%s' "$sc_have" "$sc_id")
        done
        if [ "$sc_granted" -gt 0 ]; then
          echo "  granted $sc_granted app(s); relaunch apps that were already running"
          sudo -u ${config.defaultUser} launchctl kickstart -k \
            "gui/$(id -u ${config.defaultUser})/com.apple.tccd" 2>/dev/null || true
        fi
      ''
    );
  };
}
