# The shared headless Chrome, as a container in the browser-session pod. The
# image carries the host's fontconfig, timezone and locale so the fingerprint
# matches the host unit it replaces.
{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.browser-session;
      name = "browser-session-chrome";
      image = "localhost/${name}:latest";
      uid = toString config.users.users.chrome-headless.uid;
      gid = toString config.users.groups.chrome-headless.gid;

      chrome-image = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/${name}";
        tag = "latest";
        contents = [ cfg.chrome.package ];
        extraCommands = ''
          mkdir -p etc tmp
          chmod 1777 tmp
          cp -r ${config.environment.etc.fonts.source} etc/fonts
        '';
        config = {
          Cmd = cfg.chrome.command;
          WorkingDir = cfg.chrome.dataDir;
          Env =
            {
              FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
              HOME = cfg.chrome.dataDir;
              LANG = config.i18n.defaultLocale;
              LOCALE_ARCHIVE = "${config.i18n.glibcLocales}/lib/locale/locale-archive";
              TZ = config.time.timeZone;
              TZDIR = "${pkgs.tzdata}/share/zoneinfo";
            }
            // cfg.chrome.environment
            |> lib.mapAttrsToList (n: v: "${n}=${v}");
        };
      };
    in
    {
      virtualisation.oci-containers.containers.${name} = {
        autoStart = true;
        imageFile = chrome-image;
        inherit image;
        user = "${uid}:${gid}";
        volumes = [
          "${cfg.chrome.dataDir}:${cfg.chrome.dataDir}"
          # Chrome reads it for its policy client; the host unit saw it too.
          "/etc/machine-id:/etc/machine-id:ro"
        ];
        extraOptions = [
          "--pod=${cfg.pod}"
          # GPU device nodes plus the driver libraries under /run/opengl-driver.
          "--device=nvidia.com/gpu=all"
        ];
      };

      systemd.services."podman-${name}" = {
        after = [ "browser-session-pod.service" ];
        requires = [ "browser-session-pod.service" ];
        partOf = [ "browser-session-pod.service" ];
        # A lock left by an unclean stop names a hostname and pid that the new
        # container can collide with, and Chrome then refuses the profile. This
        # container is the profile's only user, so any lock is stale here.
        preStart = ''
          rm -f ${cfg.chrome.dataDir}/Singleton{Lock,Socket,Cookie}
        '';
      };
    };
}
