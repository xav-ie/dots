# A durable record of every user-unit failure.
#
# Why this exists: timer-driven `oneshot` units are invisible to
# `systemctl --failed`. The unit fails, the timer fires again, and it settles
# back to `inactive (dead)` with Result=success from the latest run — failure
# state never accumulates. On 2026-08-02 process-logger had failed 37
# consecutive times and neverest 26, while every health check reported the
# system clean.
#
# So this is edge-triggered, not level-triggered: OnFailure= fires on each
# failure as it happens and cannot miss one, whereas polling unit state samples
# a condition that exists for milliseconds.
#
# Deliberately a file append rather than notify-send: desktop notifications
# need a live graphical session and DBUS_SESSION_BUS_ADDRESS, so they fail
# silently over SSH or on a headless boot — precisely when you most want the
# record.
{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    let
      # Absolute store paths throughout. systemd user services run with a
      # minimal PATH: assuming `id` and `ps` were on it is what broke neverest
      # and process-logger in the first place.
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
          # Last few lines of the unit's own output, indented, so the log is
          # self-contained and you needn't go digging in journalctl.
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
