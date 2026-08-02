# A durable record of every user-unit failure. Timer-driven oneshots are
# invisible to `systemctl --failed` — they settle back to inactive/success, so
# failure state never accumulates. OnFailure= is edge-triggered and cannot miss
# one. A file rather than notify-send, which needs a live graphical session.
{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    let
      # Absolute store paths throughout: systemd user services run with a
      # minimal PATH.
      recordFailure = pkgs.writeShellScript "record-unit-failure" ''
        set -u
        unit="''${1:-unknown}"
        log="''${XDG_STATE_HOME:-$HOME/.local/state}/unit-failures.log"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$log")"

        result=$(${pkgs.systemd}/bin/systemctl --user show "$unit" -p Result --value 2>/dev/null)
        status=$(${pkgs.systemd}/bin/systemctl --user show "$unit" -p ExecMainStatus --value 2>/dev/null)

        {
          ${pkgs.coreutils}/bin/printf '%s  %-34s result=%-11s exit=%s\n' \
            "$(${pkgs.coreutils}/bin/date -Is)" "$unit" "''${result:-?}" "''${status:-?}"
          ${pkgs.systemd}/bin/journalctl --user-unit "$unit" -n 5 --no-pager -o cat 2>/dev/null \
            | ${pkgs.gnused}/bin/sed 's/^/        /'
        } >> "$log"
      '';
    in
    {
      systemd.user.services."unit-failure@" = {
        Unit.Description = "Record failure of %I";
        Service = {
          Type = "oneshot";
          ExecStart = "${recordFailure} %I";
        };
      };

      # `unit-failures` prints the log; `unit-failures -f` follows it.
      home.packages = [
        (pkgs.writeShellScriptBin "unit-failures" ''
          log="''${XDG_STATE_HOME:-$HOME/.local/state}/unit-failures.log"
          [ -f "$log" ] || { echo "no failures recorded ($log)"; exit 0; }
          exec ${pkgs.coreutils}/bin/tail ''${1:+"$1"} -n 50 "$log"
        '')
      ];
    };
}
