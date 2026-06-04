{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.pkgs-mine.notification-center ];

    # Resident AGS notification daemon: owns org.freedesktop.Notifications and
    # renders the toast popups + control center.
    #
    # Type=dbus with the well-known name means systemd treats the unit as started
    # only once the bus name is actually owned. Anything that connects as a proxy
    # (the bar's `notifctl -swb`) must order After this — otherwise it could grab
    # the name first and become a headless daemon. See home-manager/linux/bar.
    systemd.user.services.notification-center = {
      Unit = {
        Description = "AGS notification center";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${pkgs.pkgs-mine.notification-center}/bin/notification-center";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
