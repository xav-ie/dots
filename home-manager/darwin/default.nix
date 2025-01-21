{ pkgs, ... }:
{
  imports = [
    ../programs/sketchybar
    ../programs/pueue
  ];

  config = {
    home = {
      stateVersion = "23.11";
      sessionVariables = { };
      packages = with pkgs; [
        morlana # better nix build on mac
        fix-yabai
      ];
    };
  };
}
