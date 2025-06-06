{
  config,
  lib,
  pkgs,
  system,
  inputs,
  ...
}:
let
  pkgs-bleeding = inputs.nixpkgs-bleeding.legacyPackages.${system};
in
{
  options = {
    services.home-assistant.mediaDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "The directory where media is stored";
      example = "/media";
      default = null;
    };
  };

  config = {
    services = {
      home-assistant = {
        enable = true;
        # Fix govee-local-api not setting the lights all the time
        # pkgs-bleeding needing because poetry-core>=2.0.0 is not on stable
        # and I don't feel like overriding *another* sub-dependency
        package = pkgs-bleeding.home-assistant.override {
          packageOverrides = _: _: {
            govee-local-api = pkgs-bleeding.python313Packages.govee-local-api.overridePythonAttrs (_: {
              version = "2.0.2";
              src = pkgs.fetchFromGitHub {
                owner = "akash329d";
                repo = "govee-local-api";
                rev = "develop";
                hash = "sha256-ChI/rIZwT/YMXFD83N1/cIIYkio318S3p1IgVu+P1sY=";
              };
            });
          };
        };
        mediaDir = "/media/hass";

        config = {
          # You first need to make sure there is at least empty
          # automations.yaml in /var/lib/hass or this will not work. Same goes
          # for scripts.yaml, scenes.yaml and groups.yaml
          # Please see ../systemd.nix
          "automation ui" = "!include automations.yaml";
          "scene ui" = "!include scenes.yaml";
          "script ui" = "!include scripts.yaml";
          "group ui" = "!include groups.yaml";

          default_config = { };

          homeassistant =
            let
              inherit (config.services.home-assistant) mediaDir;
              isDefined = x: x != null;
            in
            {
              temperature_unit = "C";
              media_dirs = lib.attrsets.optionalAttrs (isDefined mediaDir) { media = mediaDir; };
              allowlist_external_dirs = lib.lists.optional (isDefined mediaDir) mediaDir;
            };
        };

        extraComponents =
          # default config
          [
            "assist_pipeline"
            "backup"
            "bluetooth"
            "cloud"
            "config"
            "conversation"
            "dhcp"
            "energy"
            "go2rtc"
            "history"
            "homeassistant_alerts"
            "image_upload"
            "logbook"
            "media_source"
            "mobile_app"
            "my"
            "ssdp"
            "stream"
            "sun"
            "usb"
            "webhook"
            "zeroconf"
          ]
          # my additions
          ++ [
            "apple_tv"
            "govee_light_local"
            "homekit"
            "homekit_controller"
            # Recommended for fast zlib compression
            # https://www.home-assistant.io/integrations/isal
            "isal"
            "matter"
            "met"
            "thread"
            "xiaomi_aqara"
            "zha"
          ];
      };
    };

    systemd = {
      # fix bug in ha not creating these files...
      tmpfiles.rules =
        let
          hassDir = config.services.home-assistant.configDir;
          inherit (config.services.home-assistant) mediaDir;
          isDefined = x: x != null;
        in
        lib.lists.optionals config.services.home-assistant.enable [
          "f ${hassDir}/automations.yaml 0755 hass hass"
          "f ${hassDir}/scenes.yaml      0755 hass hass"
          "f ${hassDir}/scripts.yaml     0755 hass hass"
          # "d /var/lib/hass/backups 0750 hass hass"
        ]
        # blegh... I guess this is how we must configure media dir
        ++ lib.lists.optional (isDefined mediaDir) "d ${mediaDir} 0777 hass hass";
    };

  };
}
