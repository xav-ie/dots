# The phone's view of this machine's herd. Upstream's wizard would generate a
# relay key and its own Cloudflare tunnel; the existing tunnel carries it
# instead, and `serve` reads everything from the environment.
#
# Keyless on purpose: Access on the hostname is the gate, so there is no key and
# no QR pairing, and authorisation falls to the origin check. The cost, per
# upstream's docs/security.md, is that keyless connections add no
# application-layer encryption — Cloudflare sees agent traffic in the clear.
{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.herdr-mobile-relay;
    in
    {
      options.services.herdr-mobile-relay = {
        origin = lib.mkOption {
          type = lib.types.str;
          default = "https://herdr-mobile-relay.lalala.casa";
          description = ''
            Public origin the phone app is served from. Must match the tunnel's
            published hostname exactly, or the origin check rejects every
            browser.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 38975;
          description = ''
            Loopback port serving the phone app and its websocket, and what the
            Cloudflare tunnel route points at. Upstream defaults to 8375.
          '';
        };
      };

      config = {
        home.packages = [ pkgs.pkgs-mine.herdr-mobile-relay ];

        systemd.user.services.herdr-mobile-relay = {
          Unit = {
            Description = "herdr mobile relay";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.pkgs-mine.herdr-mobile-relay} serve";
            # Drives herdr over its socket API, and git for worktree actions.
            Environment = [
              "HERDR_ALLOWED_ORIGINS=${cfg.origin}"
              "HERDR_RELAY_HOST=127.0.0.1"
              "HERDR_RELAY_PORT=${toString cfg.port}"
              "HERDR_WEB_ROOT=${pkgs.pkgs-mine.herdr-mobile-relay}/${pkgs.pkgs-mine.herdr-mobile-relay.webRoot}"
              # procps: pane resizing resolves a pane's TTY by shelling out to
              # `ps`, and reports a missing binary as "does not have a TTY".
              "PATH=${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.herdr
                  pkgs.procps
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
