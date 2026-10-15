{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.speech;
      dictate = pkgs.pkgs-mine.dictate;
      # Straight to the daemon over D-Bus: no process spawned per keypress, so
      # tap vs hold timing stays accurate.
      request =
        cmd:
        lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${pkgs.systemd}/bin/busctl --user call io.Astal.dictate /io/Astal/Application io.Astal.Application Request as 1 ${cmd}")'';
    in
    {
      config = lib.mkIf (cfg.app == "dictate") {
        home.packages = [ dictate ];

        # Tap: type live until the next tap. Hold: push-to-talk, pasted on release.
        wayland.windowManager.hyprland.settings = {
          bind = [
            {
              _args = [
                cfg.pushToTalk.hyprlandKeys
                (request "press")
              ];
            }
            {
              _args = [
                cfg.pushToTalk.hyprlandKeys
                (request "release")
                { release = true; }
              ];
            }
          ];
          layer_rule = [
            {
              match.namespace = "dictate";
              animation = "slide bottom";
              blur = true;
              ignore_alpha = 0.6;
            }
          ];
        };

        systemd.user.services.dictate = {
          Unit = {
            Description = "Live dictation into scribe";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "dbus";
            BusName = "io.Astal.dictate";
            ExecStart = "${dictate}/bin/dictate";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
