{
  flake.modules.nixos.base =
    {
      pkgs,
      ...
    }:
    {
      config = {
        # Configure systemd journal to reduce disk I/O and prevent log spam
        services.journald.extraConfig = ''
          SystemMaxUse=500M
          RuntimeMaxUse=100M
          MaxRetentionSec=1week
          RateLimitIntervalSec=30s
          RateLimitBurst=10000
        '';

        systemd = {
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
    };
}
