{
  lib,
  ...
}:
{
  imports = [
    ./hyprwhspr
    ./voquill
    ./voxtype
  ];

  options.speech = {
    app = lib.mkOption {
      type = lib.types.enum [
        "hyprwhspr"
        "voxtype"
        "voquill"
      ];
      default = "hyprwhspr";
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
    };
  };
}
