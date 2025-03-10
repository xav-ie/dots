{
  pkgs,
  ...
}:
{
  config = {
    systemd = {
      user.services.polkit-gnome-authentication-agent-1 = {
        description = "polkit-gnome-authentication-agent-1";
        wantedBy = [ "default.target" ];
        after = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };

      # must be system service due to journalctl needing elevated permissions
      # TODO: ^ is this true?
      services.clear-log = {
        description = "Clear >1 month-old logs every week";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/journalctl --vacuum-time=21d";
        };
      };
      timers.clear-log = {
        wantedBy = [ "timers.target" ];
        partOf = [ "clear-log.service" ];
        timerConfig.OnCalendar = "weekly UTC";
      };
    };
  };
}
