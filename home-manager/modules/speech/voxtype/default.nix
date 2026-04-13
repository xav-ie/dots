{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.speech;
  enabled = cfg.app == "voxtype";
in
{
  config = lib.mkIf enabled (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.voxtype
        ];

        xdg.configFile."voxtype/config.toml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/speech/voxtype/config.toml";
      }

      # Linux-only: systemd service + Hyprland keybinding
      (lib.mkIf pkgs.stdenv.isLinux {
        systemd.user.services.voxtype = {
          Unit = {
            Description = "Voxtype voice-to-text daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.voxtype}/bin/voxtype";
            Restart = "on-failure";
            RestartSec = 3;
            # GPU env vars (VOXTYPE_VULKAN_DEVICE, VK_ICD_FILENAMES, LD_LIBRARY_PATH)
            # are baked into the voxtype binary wrapper via overlay
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        wayland.windowManager.hyprland.settings = {
          # Push-to-talk: hold to record, release to transcribe
          bind = [
            "${cfg.pushToTalk.modifier}, ${cfg.pushToTalk.key}, exec, ${pkgs.voxtype}/bin/voxtype record start"
          ];
          bindr = [
            "${cfg.pushToTalk.modifier}, ${cfg.pushToTalk.key}, exec, ${pkgs.voxtype}/bin/voxtype record stop"
          ];
        };
      })
    ]
  );
}
