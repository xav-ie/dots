# airpods-mode: media play → ANC, pause → Transparency (tool: packages/airpods-mode).
# The launchd daemon + the install/re-sign activation that gives it its
# entitlements, in one darwin module.
#
# Every gate airpods-mode bypasses (AVFoundation system-audio context, Bluetooth
# TCC, MediaRemote now-playing) is unlocked by the entitlements in the re-sign
# below, which are honored only because nox boots amfi_get_out_of_my_way=1. So
# it's really a nox feature, but it rides darwin.macos (nox is the only darwin
# host) and degrades to a harmless no-op daemon on any Mac without that boot-arg.
_:
{
  flake.modules.darwin.macos =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # airpods-mode --daemon: flips AirPods to ANC on media play, Transparency on
      # pause. Runs the re-signed ~/Applications copy (the store binary is ad-hoc
      # signed with no entitlements); the activation below installs + re-signs it
      # and kickstarts this agent when the package changes. AIRPODS_PKG flips the
      # launchd config hash so it restarts on code changes.
      launchd.user.agents.airpods-mode.serviceConfig = {
        ProgramArguments = [
          "/Users/${config.defaultUser}/Applications/airpods-mode.app/Contents/MacOS/airpods-mode"
          "--daemon"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.AIRPODS_PKG = "${pkgs.pkgs-mine.airpods-mode}";
        StandardOutPath = "/tmp/airpods-mode.out.log";
        StandardErrorPath = "/tmp/airpods-mode.err.log";
      };

      # Install the .app to ~/Applications and re-sign it ad-hoc with
      # airpods-mode.entitlements. The entitlements (honored only under
      # amfi_get_out_of_my_way=1, no real cert needed) grant:
      #   - com.apple.avfoundation.allow-system-wide-context → set listening mode
      #   - com.apple.private.tcc.allow (Bluetooth) → IOBluetooth for `list`
      #   - com.apple.mediaremote.* → --daemon reads now-playing state
      # The bundle id is com.apple.airpods-mode (baked in the package) because
      # mediaremoted gates now-playing by com.apple.* prefix. No tcc-grant:
      # Bluetooth TCC rows are inert (the entitlement is what works). Marker-
      # guarded: re-runs (and restarts the daemon) when the pkg changes.
      system.activationScripts.postActivation.text =
        lib.mkAfter # sh
          ''
            airpods_pkg="${pkgs.pkgs-mine.airpods-mode}"
            airpods_marker="/var/lib/nix-darwin/airpods-mode-pkg"
            if [ "$(cat "$airpods_marker" 2>/dev/null)" != "$airpods_pkg" ]; then
              echo "🎧 Installing + re-signing ~/Applications/airpods-mode.app"
              airpods_uid=$(id -u ${config.defaultUser})
              airpods_app="/Users/${config.defaultUser}/Applications/airpods-mode.app"
              sudo -u ${config.defaultUser} mkdir -p "/Users/${config.defaultUser}/Applications"
              sudo -u ${config.defaultUser} rm -rf "$airpods_app"
              sudo -u ${config.defaultUser} cp -R "$airpods_pkg/Applications/airpods-mode.app" "$airpods_app"
              sudo -u ${config.defaultUser} chmod -R u+w "$airpods_app"
              sudo -u ${config.defaultUser} /usr/bin/codesign --force --sign - \
                --identifier com.apple.airpods-mode \
                --entitlements "$airpods_pkg/airpods-mode.entitlements" "$airpods_app" 2>/dev/null || true
              sudo -u ${config.defaultUser} launchctl kickstart -k \
                "gui/$airpods_uid/org.nixos.airpods-mode" 2>/dev/null || true
              mkdir -p "$(dirname "$airpods_marker")"
              echo "$airpods_pkg" > "$airpods_marker"
            fi
          '';
    };
}
