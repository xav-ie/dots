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
            # Timer-driven oneshot: invisible to `systemctl --failed`. This had
            # failed silently on every run. See modules/home-linux/unit-failure-log.nix.
            OnFailure = "unit-failure@%n.service";
          };
          Service = {
            Type = "oneshot";
            # neverest runs the account's `auth.cmd` through a shell it looks up
            # on PATH. A systemd user service inherits only systemd's own bin,
            # so there was no `sh` to run it with and every sync died with
            #   cannot get imap password from global keyring
            #     cannot get secret from command
            #       No such file or directory (os error 2)
            # which reads like a missing password file but is a missing shell.
            # Verified: same script + PATH set = "Account work successfully
            # synchronized!". Absolute paths in auth.cmd are not enough on their
            # own, because the shell that runs them must also be resolvable.
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
                  # $XDG_RUNTIME_DIR, not /run/user/$(id -u): systemd user
                  # services run with a minimal PATH that has no `id`, so the
                  # substitution came back empty and the path collapsed to
                  # /run/user//neverest.lock — root-owned, so flock failed with
                  # EACCES on every run and mail never synced. systemd always
                  # sets XDG_RUNTIME_DIR for user units, and it needs no binary.
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
