{ pkgs, ... }:
{
  imports = [
    ../programs/sketchybar
  ];

  config = {
    home = {
      stateVersion = "23.11";
      sessionVariables = { };
      packages = with pkgs.pkgs-mine; [
        fix-yabai
        focus-or-open-application
        move-pip
      ];
    };
  };
}
