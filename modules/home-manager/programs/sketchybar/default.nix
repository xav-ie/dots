{ pkgs, ... }:
let
  mkSketchybarScript =
    name: path:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.sketchybar ];
      text = path;
    }
    + "/bin/${name}";

  # so that I don't have to hard-code $HOME
  sketchybarWrapper = pkgs.writeShellScript "sketchybar-wrapper" ''
    pgrep sketchybar || \
    exec ${pkgs.sketchybar}/bin/sketchybar --config "$HOME/.config/sketchybar/sketchybarrc" "$@"
  '';
in
{
  config = {
    home = {
      packages = [ pkgs.sketchybar ];

      file = {
        ".config/sketchybar/sketchybarrc".source = mkSketchybarScript "sketchybarrc" ./sketchybarrc;
        ".config/sketchybar/plugins/battery.sh".source = mkSketchybarScript "battery" ./plugins/battery.sh;
        ".config/sketchybar/plugins/clock.sh".source = mkSketchybarScript "clock" ./plugins/clock.sh;
        ".config/sketchybar/plugins/front_app.sh".source = mkSketchybarScript "front_app" ./plugins/front_app.sh;
        ".config/sketchybar/plugins/space.sh".source = mkSketchybarScript "space" ./plugins/space.sh;
        ".config/sketchybar/plugins/volume.sh".source = mkSketchybarScript "volume" ./plugins/volume.sh;
      };
    };

    launchd.agents.sketchybar = {
      enable = true;
      config = {
        Debug = true;
        Program = "${sketchybarWrapper}";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/sketchybar.log";
        StandardErrorPath = "/tmp/sketchybar.err";
        StartInterval = 5;
      };
    };
  };
}
