{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.security.tcc;

  tccGrant = pkgs.pkgs-mine.tcc-grant;

  # Generate grant commands for all apps and services
  grantCommands = lib.concatMapStringsSep "\n" (
    app:
    let
      services = lib.concatMapStringsSep "\n" (
        service:
        "${tccGrant}/bin/tcc-grant --service ${service} --bundle-id ${app.bundleId} --db \"$TCC_DB\""
      ) app.services;
    in
    ''
      # ${app.bundleId}
      ${services}
    ''
  ) cfg.apps;
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
    # Grant permissions during system activation (runs as root, so use explicit user path)
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Ensuring TCC permissions for ${config.defaultUser}..."
      TCC_DB="/Users/${config.defaultUser}/Library/Application Support/com.apple.TCC/TCC.db"
      ${grantCommands}
    '';
  };
}
