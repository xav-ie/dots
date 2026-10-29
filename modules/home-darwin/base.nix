# macOS home-manager darwin package set (yabai/sketchybar helpers).
{
  flake.modules.homeManager.darwin =
    { pkgs, ... }:
    {
      config = {
        home = {
          packages = with pkgs.pkgs-mine; [
            fix-yabai
            move-pip
            polish-recording
            # The app binary is also the CLI: `screenshare-ui show|hide|panel`.
            screenshare-ui
            sketchybar-battery
          ];
        };
      };
    };
}
