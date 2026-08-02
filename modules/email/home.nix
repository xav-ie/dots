{
  flake.modules.homeManager.linux =
    {
      pkgs,
      lib,
      ...
    }:
    let
      emailData = import ./_accounts.nix;
    in
    {
      config = {
        home.packages = [
          pkgs.himalaya
          pkgs.msmtp
          pkgs.neverest
        ];

        # Ensure Maildir directories exist (each needs cur/new/tmp subdirs)
        systemd.user.tmpfiles.rules =
          let
            accounts = map (acc: acc.name) emailData.accounts;
            inherit (emailData) folders;
            subdirs = [
              "cur"
              "new"
              "tmp"
            ];
            mkRules =
              account: folder: map (sub: "d %h/.mail/${account}/${folder.name}/${sub} 0700 - - -") subdirs;
          in
          accounts |> lib.concatMap (account: lib.concatMap (mkRules account) folders);

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
            ExecStart = toString (
              pkgs.writeShellScript "neverest-sync" # sh
                ''
                  # $XDG_RUNTIME_DIR, not /run/user/$(id -u): there is no `id`
                  # on the service PATH, and systemd always sets this.
                  ${pkgs.util-linux}/bin/flock \
                    --nonblock \
                    --conflict-exit-code 0 \
                    "$XDG_RUNTIME_DIR/neverest.lock" \
                    ${lib.getExe pkgs.neverest} sync
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
