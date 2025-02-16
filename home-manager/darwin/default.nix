{ pkgs, ... }:
{
  imports = [
    ../programs/sketchybar
  ];

  config = {
    home = {
      stateVersion = "23.11";
      sessionVariables = { };
      packages =
        (with pkgs; [
          morlana # better nix build on mac
        ])
        ++ (with pkgs.pkgs-mine; [
          fix-yabai
        ]);
    };
  };
}
