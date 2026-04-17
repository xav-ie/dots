{
  config,
  lib,
  pkgs,
  ...
}:
let
  screencast-dnd = pkgs.writeNuApplication {
    name = "screencast-dnd";
    runtimeInputs = [
      config.services.swaync.package
      pkgs.pipewire
    ];
    text = builtins.readFile ./screencast-dnd.nu;
  };
in
{
  config = {
    systemd.user.services.screencast-dnd = {
      Unit = {
        Description = "Auto-toggle swaync DND during xdg-desktop-portal screencasts";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "pipewire.service"
          "swaync.service"
        ];
      };
      Service = {
        ExecStart = lib.getExe screencast-dnd;
        Restart = "always";
        RestartSec = 2;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
