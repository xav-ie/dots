{
  flake.modules.homeManager.linux =
    { pkgs, ... }:
    {
      config = {
        # Resident overlay that frames the screen in red while a screencast is live.
        # It watches pw-mon for xdph streaming nodes, so it only needs pipewire to be
        # up; the windows stay hidden until a cast starts.
        systemd.user.services.screencast-border = {
          Unit = {
            Description = "Red screen-share border overlay";
            PartOf = [ "graphical-session.target" ];
            After = [
              "graphical-session.target"
              "pipewire.service"
            ];
          };
          Service = {
            ExecStart = "${pkgs.pkgs-mine.screencast-border}/bin/screencast-border";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
