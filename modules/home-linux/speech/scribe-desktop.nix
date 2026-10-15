{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.speech;
      scribe-desktop = pkgs.pkgs-mine.scribe-desktop;
      # Straight to the daemon over D-Bus: no process spawned per keypress, so
      # tap vs hold timing stays accurate.
      request =
        cmd:
        lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${pkgs.systemd}/bin/busctl --user call io.Astal.scribe-desktop /io/Astal/Application io.Astal.Application Request as 1 ${cmd}")'';
    in
    {
      config = lib.mkIf (cfg.app == "scribe-desktop") {
        home.packages = [ scribe-desktop ];

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
              match.namespace = "scribe-desktop";
              animation = "slide bottom";
              blur = true;
              ignore_alpha = 0.6;
            }
          ];
        };

        systemd.user.services.scribe-desktop = {
          Unit = {
            Description = "Live dictation into scribe";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "dbus";
            BusName = "io.Astal.scribe-desktop";
            ExecStart = "${scribe-desktop}/bin/scribe-desktop";
            Environment = [
              "SCRIBE_URL=wss://scribe.lalala.casa/ws"
              "SCRIBE_TOKEN_FILE=${osConfig.sops.secrets."scribe/token".path}"
            ];
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
