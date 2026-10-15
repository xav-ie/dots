{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      # Resident spotlight launcher so the picker keybinds open instantly; the
      # binds forward their mode to this instance. As a unit, sd-switch restarts
      # it whenever the pickers package changes.
      systemd.user.services.spotlight = {
        Unit = {
          Description = "AGS spotlight launcher";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "dbus";
          BusName = "io.Astal.spotlight";
          ExecStart = "${pkgs.pkgs-mine.pickers}/bin/spotlight --daemon";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
