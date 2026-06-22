{
  flake.modules.darwin.macos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.security.tcc;

      tccGrant = pkgs.pkgs-mine.tcc-grant;

      # These services live in the SYSTEM TCC.db (/Library/...); everything else
      # (Camera, Microphone, AppleEvents, …) lives in the per-user db. A grant to
      # the wrong db is silently inert — the long-standing bug this fixes.
      systemServices = [
        "Accessibility"
        "FullDiskAccess"
        "ScreenCapture"
        "DeveloperTool"
        "InputMonitoring"
        "PostEvent"
      ];
      dbFor = service: if builtins.elem service systemServices then "$SYS_TCC_DB" else "$USER_TCC_DB";

      # Generate grant commands for all apps and services
      grantCommands =
        cfg.apps
        |> lib.concatMapStringsSep "\n" (
          app:
          let
            services =
              app.services
              |> lib.concatMapStringsSep "\n" (
                service:
                "${tccGrant}/bin/tcc-grant --service ${service} --bundle-id ${app.bundleId} --db \"${dbFor service}\""
              );
          in
          ''
            # ${app.bundleId}
            ${services}
          ''
        );
    in
    {
      options.security.tcc = {
        enable = lib.mkEnableOption "declarative TCC permission management";

        apps = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                bundleId = lib.mkOption {
                  type = lib.types.str;
                  description = "Application bundle identifier (e.g., org.whispersystems.signal-desktop)";
                  example = "org.whispersystems.signal-desktop";
                };

                services = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.enum [
                      # Media
                      "Camera"
                      "Microphone"
                      "ScreenCapture"
                      # Automation
                      "Accessibility"
                      "AppleEvents"
                      # Data
                      "AddressBook"
                      "Calendar"
                      "Reminders"
                      "Photos"
                      # System
                      "SpeechRecognition"
                      "FullDiskAccess"
                      "DownloadsFolder"
                      "DesktopFolder"
                      "DocumentsFolder"
                      "Location"
                      "FocusStatus"
                    ]
                  );
                  default = [
                    "Camera"
                    "Microphone"
                  ];
                  description = "TCC services to grant access to";
                };
              };
            }
          );
          default = [ ];
          description = "Applications to grant TCC permissions to";
          example = lib.literalExpression ''
            [
              { bundleId = "org.whispersystems.signal-desktop"; services = [ "Camera" "Microphone" "ScreenCapture" ]; }
              { bundleId = "com.mitchellh.ghostty"; services = [ "Accessibility" "FullDiskAccess" ]; }
            ]
          '';
        };
      };

      config = lib.mkIf (cfg.enable && cfg.apps != [ ]) {
        # Grant at activation (runs as root). System-db writes work because SIP is
        # off; reload tccd so it picks them up without a logout. tcc-grant skips
        # already-allowed entries, so existing System-Settings grants are safe.
        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "Ensuring TCC permissions for ${config.defaultUser}..."
          USER_TCC_DB="/Users/${config.defaultUser}/Library/Application Support/com.apple.TCC/TCC.db"
          SYS_TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
          ${grantCommands}
          sudo -u ${config.defaultUser} launchctl kickstart -k \
            "gui/$(id -u ${config.defaultUser})/com.apple.tccd" 2>/dev/null || true
        '';
      };
    };
}
