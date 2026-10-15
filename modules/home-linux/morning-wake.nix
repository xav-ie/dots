{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      # 09:00: wake the screens and hold an idle inhibit for 10 min; on release hypridle restarts its timers.
      systemd.user.services.morning-wake = {
        Unit = {
          Description = "Wake monitors at 09:00 for 10 minutes";
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "morning-wake" ''
            hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
            exec ${pkgs.systemd}/bin/systemd-inhibit --what=idle --who=morning-wake --why="09:00 wake" ${pkgs.coreutils}/bin/sleep 600
          ''}";
        };
      };
      systemd.user.timers.morning-wake = {
        Unit.PartOf = [ "graphical-session.target" ];
        Timer.OnCalendar = "*-*-* 09:00:00";
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
