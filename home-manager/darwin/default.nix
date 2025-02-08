{ pkgs, toplevel, ... }:
let
  myPackages = toplevel.self.packages.${pkgs.system};
in
{
  imports = [
    ../programs/sketchybar
    ../programs/pueue
  ];

  config = {
    home = {
      stateVersion = "23.11";
      sessionVariables = { };
      packages =
        (with pkgs; [
          morlana # better nix build on mac
        ])
        ++ (with myPackages; [
          fix-yabai
        ]);
    };
  };
}
