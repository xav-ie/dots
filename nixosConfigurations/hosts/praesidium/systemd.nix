{
  config,
  lib,
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

      # fix bug in ha not creating these files...
      tmpfiles.rules =
        let
          hassDir = config.services.home-assistant.configDir;
          mediaDir = config.services.home-assistant.mediaDir;
          isDefined = x: x != null;
        in
        lib.lists.optionals config.services.home-assistant.enable [
          "f ${hassDir}/automations.yaml 0755 hass hass"
          "f ${hassDir}/scenes.yaml      0755 hass hass"
          "f ${hassDir}/scripts.yaml     0755 hass hass"
          # "d /var/lib/hass/backups 0750 hass hass"
        ]
        # blegh... I guess this is how we must configure media dir
        ++ lib.lists.optional (isDefined mediaDir) "d ${mediaDir} 0777 hass hass";

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
