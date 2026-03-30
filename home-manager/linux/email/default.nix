{
  pkgs,
  lib,
  ...
}:
let
  emailData = import ../../../lib/email-accounts.nix;
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
      lib.concatMap (account: lib.concatMap (mkRules account) folders) accounts;

    # Periodic mail sync — config at ~/.config/neverest/config.toml via sops template
    # flock prevents concurrent runs
    systemd.user.services.neverest = {
      Unit.Description = "Sync mail with neverest";
      Service = {
        Type = "oneshot";
        ExecStart = toString (
          pkgs.writeShellScript "neverest-sync" ''
            ${pkgs.util-linux}/bin/flock \
              --nonblock \
              --conflict-exit-code 0 \
              /run/user/$(id -u)/neverest.lock \
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
}
