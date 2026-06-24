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
            # Apps whose bundle we mutate in place (e.g. Firefox autoconfig
            # injection) lose their Apple seal; under amfi_get_out_of_my_way=1 tccd
            # then treats them as unsigned platform binaries and denies everything.
            # The fix is to re-sign them with an Apple-anchored cert — that re-sign
            # happens in the owning module's *user-level* activation (it needs
            # keychain access) and runs before this one. Here we only pin the csreq:
            # we read the bundle's *current* designated requirement (--designated-from)
            # rather than a cdhash (a cdhash pin is legacy-SHA-1 and never matches a
            # modern SHA-256 signature) — so it auto-tracks whatever cert the re-sign
            # used and survives cert rotation with no config change.
            drArg = lib.optionalString (app.appPath != "") " --designated-from \"${app.appPath}\"";

            services =
              app.services
              |> lib.concatMapStringsSep "\n" (
                service:
                "${tccGrant}/bin/tcc-grant --service ${service} --bundle-id ${app.bundleId} --db \"${dbFor service}\"${drArg}"
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

                appPath = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = ''
                    Absolute path to the .app bundle. When set, the grant is pinned to
                    the bundle's current designated requirement (read at activation)
                    instead of a bare bundle-id match — required for re-signed apps,
                    whose ad-hoc/cert seal has no anchor a bundle-id grant can trust.
                  '';
                  example = "/Applications/Firefox.app";
                };

                resignIdentity = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = ''
                    Coarse codesign-identity matcher (a substring of the cert name, e.g.
                    "Apple Development") that the app's bundle is re-signed with. This
                    module does NOT use it directly — the owning module reads it (via
                    osConfig) and resolves the exact identity from the login keychain at
                    activation, so cert rotation needs no config change. Declared here so
                    intent lives next to the grant; pair with appPath.

                    Needed for bundles mutated in place — e.g. Firefox, whose autoconfig
                    injection breaks the Apple seal; under amfi_get_out_of_my_way=1 a
                    broken/ad-hoc seal makes tccd treat the app as an unsigned platform
                    binary and deny camera/mic/screen-capture. Must resolve to an
                    Apple-anchored cert (ad-hoc does not work).
                  '';
                  example = "Apple Development";
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
