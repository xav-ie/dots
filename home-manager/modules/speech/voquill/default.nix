{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.speech;
  enabled = cfg.app == "voquill";
in
{
  config = lib.mkIf enabled (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.voquill
        ];
      }

      # Linux-only: systemd service + Hyprland keybinding
      (lib.mkIf pkgs.stdenv.isLinux {
        wayland.windowManager.hyprland.settings = {
          # Push-to-talk: hold to record, release to stop
          bind = [
            "${cfg.pushToTalk.modifier}, ${cfg.pushToTalk.key}, exec, $HOME/.config/com.voquill.desktop/trigger-hotkey.sh dictate"
          ];
          bindr = [
            "${cfg.pushToTalk.modifier}, ${cfg.pushToTalk.key}, exec, $HOME/.config/com.voquill.desktop/trigger-hotkey.sh dictate"
          ];
        };

        systemd.user.services.voquill = {
          Unit = {
            Description = "Voquill voice typing application";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.voquill}/bin/voquill";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      })
    ]
  );
}
