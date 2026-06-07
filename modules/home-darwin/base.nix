# macOS home-manager darwin package set (yabai/sketchybar helpers).
{
  flake.modules.homeManager.darwin =
    { pkgs, ... }:
    {
      config = {
        home = {
          packages = with pkgs.pkgs-mine; [
            fix-yabai
            focus-or-open-application
            move-pip
            sketchybar-battery
          ];
        };
      };
    };
}
