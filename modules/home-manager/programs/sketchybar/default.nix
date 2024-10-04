{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      sketchybar
    ];
    file.".config/sketchybar/sketchybarrc".source = ./sketchybarrc;
    file.".config/sketchybar/plugins/battery.sh".source = ./plugins/battery.sh;
    file.".config/sketchybar/plugins/clock.sh".source = ./plugins/clock.sh;
    file.".config/sketchybar/plugins/front_app.sh".source = ./plugins/front_app.sh;
    file.".config/sketchybar/plugins/space.sh".source = ./plugins/space.sh;
    file.".config/sketchybar/plugins/volume.sh".source = ./plugins/volume.sh;
  };
}
