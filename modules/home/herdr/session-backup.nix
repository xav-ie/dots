# herdr deletes session.json once its last workspace closes, and at shutdown the
# panes can die before the server does, so it closes every workspace and wipes the
# session it should restore. Keep hourly copies (a week's worth) so a wiped or
# freshly-reset session never overwrites the last good one. To restore:
# `herdr server stop`, copy a backup over ~/.config/herdr/session.json, run herdr.
{
  flake.modules.homeManager.linux =
    { pkgs, lib, ... }:
    let
      backup = pkgs.writeShellApplication {
        name = "herdr-session-backup";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.jq
        ];
        text = ''
          src="$HOME/.config/herdr/session.json"
          dir="$HOME/.local/state/herdr/session-backups"
          jq -e '.workspaces | length > 0' "$src" >/dev/null 2>&1 || exit 0
          mkdir -p "$dir"
          cp "$src" "$dir/session-$(date +%Y%m%d-%H).json"
          find "$dir" -name 'session-*.json' -mtime +7 -delete
        '';
      };
    in
    {
      systemd.user.services.herdr-session-backup = {
        Unit.Description = "Back up the herdr session file";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe backup;
        };
      };
      systemd.user.timers.herdr-session-backup = {
        Unit.Description = "Back up the herdr session file every 5 minutes";
        Timer.OnCalendar = "*:0/5";
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
