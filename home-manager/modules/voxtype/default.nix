{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.packages = [
        pkgs.voxtype
      ];

      xdg.configFile."voxtype/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/voxtype/config.toml";
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
        # Push-to-talk: hold SUPER+G to record, release to transcribe
        bind = [
          "SUPER, G, exec, ${pkgs.voxtype}/bin/voxtype record start"
        ];
        bindr = [
          "SUPER, G, exec, ${pkgs.voxtype}/bin/voxtype record stop"
        ];
      };
    })
  ];
}
