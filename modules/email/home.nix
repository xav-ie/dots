{
  flake.modules.homeManager.linux =
    {
      pkgs,
      lib,
      ...
    }:
    {
      config = {
        home.packages = [
          pkgs.himalaya
          pkgs.msmtp
          pkgs.neverest
        ];

        # Periodic mail sync — config at ~/.config/neverest/config.toml via sops template
        # flock prevents concurrent runs
        systemd.user.services.neverest = {
          Unit = {
            Description = "Sync mail with neverest";
            OnFailure = "unit-failure@%n.service";
          };
          Service = {
            Type = "oneshot";
            # neverest runs auth.cmd through a shell it looks up on PATH, which
            # a systemd user service does not otherwise have.
            Environment = [
              "PATH=${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                ]
              }"
            ];
            # `neverest sync` covers only the default account, so each one is
            # named. One account failing still lets the others sync, but fails
            # the unit.
            ExecStart = toString (
              pkgs.writeShellScript "neverest-sync" # sh
                ''
                  # $XDG_RUNTIME_DIR, not /run/user/$(id -u): there is no `id`
                  # on the service PATH, and systemd always sets this.
                  exec 9>"$XDG_RUNTIME_DIR/neverest.lock"
                  ${pkgs.util-linux}/bin/flock --nonblock 9 || exit 0
                  status=0
                  for account in ${lib.escapeShellArgs (map (a: a.name) (import ./_accounts.nix).accounts)}; do
                    ${lib.getExe pkgs.neverest} sync -a "$account" || status=1
                  done
                  exit $status
                ''
            );
          };
        };

        systemd.user.timers.neverest = {
          Unit.Description = "Sync mail every 15 minutes";
          Timer = {
            OnBootSec = "2min";
            OnUnitActiveSec = "15min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
