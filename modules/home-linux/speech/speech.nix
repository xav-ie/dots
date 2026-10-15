{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      ...
    }:
    {
      options.speech = {
        app = lib.mkOption {
          type = lib.types.enum [
            "scribe-desktop"
            "hyprwhspr"
            "voxtype"
            "voquill"
          ];
          default = "scribe-desktop";
          description = "Which speech-to-text application to use.";
        };

        pushToTalk = {
          modifier = lib.mkOption {
            type = lib.types.str;
            default = "SUPER";
            description = "Hyprland modifier for the push-to-talk keybinding.";
          };

          key = lib.mkOption {
            type = lib.types.str;
            default = "G";
            description = "Key for the push-to-talk keybinding.";
          };

          hyprlandKeys = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = lib.concatStringsSep " + " (
              lib.splitString " " config.speech.pushToTalk.modifier ++ [ config.speech.pushToTalk.key ]
            );
            description = "The push-to-talk chord in Hyprland's Lua bind syntax, e.g. `SUPER + G`.";
          };
        };
      };
    };
}
