# Collie — the other phone UI for the herd, running alongside herdr-mobile-relay
# so the two can be compared.
#
# bridge/config.ts reads every setting from process.env, so the unit is the
# whole configuration: no .env file, and none of upstream's collie-ctl.sh, which
# would otherwise own the build, the service and the front door.
{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.collie;
    in
    {
      options.services.collie = {
        origin = lib.mkOption {
          type = lib.types.str;
          default = "https://collie.lalala.casa";
          description = ''
            Public origin, as a full origin. The bridge is same-origin only, so
            this must match the tunnel's published hostname or the page loads
            and stays empty.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 38977;
          description = "Loopback port the bridge listens on.";
        };
      };

      config = {
        systemd.user.services.collie = {
          Unit = {
            Description = "Collie bridge";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = lib.getExe pkgs.pkgs-mine.collie;
            Environment = [
              "COLLIE_ALLOWED_ORIGINS=${cfg.origin}"
              "COLLIE_HOST=127.0.0.1"
              "COLLIE_PORT=${toString cfg.port}"
              # Host allowlist, which defeats DNS rebinding against a loopback
              # bridge. Same value, without the scheme.
              "COLLIE_PUBLIC_HOSTS=${lib.removePrefix "https://" cfg.origin}"
              "COLLIE_PUBLIC_URL=${cfg.origin}"
              "PATH=${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.herdr
                ]
              }"
            ];
            Restart = "on-failure";
            RestartSec = 10;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
