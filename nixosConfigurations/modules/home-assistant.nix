{
  config,
  lib,
  pkgs,
  system,
  inputs,
  ...
}:
let
  pkgs-homeassistant = inputs.nixpkgs-homeassistant.legacyPackages.${system};
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
        # pkgs-homeassistant needing because poetry-core>=2.0.0 is not on stable
        # and I don't feel like overriding *another* sub-dependency
        package = pkgs-homeassistant.home-assistant.override {
          packageOverrides = self: _: {
            govee-local-api = pkgs-homeassistant.python313Packages.govee-local-api.overridePythonAttrs (_: {
              version = "2.0.2";
              src = pkgs.fetchFromGitHub {
                owner = "akash329d";
                repo = "govee-local-api";
                rev = "develop";
                hash = "sha256-ChI/rIZwT/YMXFD83N1/cIIYkio318S3p1IgVu+P1sY=";
              };
            });
            protobuf = pkgs-homeassistant.python313Packages.protobuf.overridePythonAttrs (old: {
              version = "6.31.1";
              src = pkgs.fetchPypi {
                pname = "protobuf";
                version = "6.31.1";
                hash = "sha256-2MrEyYLwuVek3HOoDi6iT6sI5nnA3p3rg19KEtaaypo=";
              };
            });
            pyatv =
              (pkgs-homeassistant.python313Packages.pyatv.override {
                protobuf = self.protobuf;
              }).overridePythonAttrs
                (old: {
                  version = "0.16.1";
                  src = pkgs.fetchFromGitHub {
                    owner = "postlund";
                    repo = "pyatv";
                    rev = "v0.16.1";
                    hash = "sha256-b5u9u5CD/1W422rCxHvoyBqT5CuBAh68/EUBzNDcXoE=";
                  };
                });
          };
          # home-assistant freaks out if these are not added
          extraPackages =
            ps: with ps; [
              getmac
              spotifyaio
              govee-ble
            ];
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
