{ lib, pkgs, ... }:
let
  writeNuApplication = import ../../../lib/writeNuApplication { inherit lib pkgs; };
  mkSketchybarScript =
    name: path:
    writeNuApplication {
      inherit name;
      runtimeInputs = [ pkgs.sketchybar ];
      text = builtins.readFile path;
    }
    + "/bin/${name}";

  # so that I don't have to hard-code $HOME
  sketchybarWrapper = pkgs.writeShellScript "sketchybar-wrapper" ''
    pgrep sketchybar || \
    exec ${pkgs.sketchybar}/bin/sketchybar --config "$HOME/.config/sketchybar/sketchybarrc" "$@"
  '';

  # TODO: get this to work
  # sketchybarReload = pkgs.writeShellScript "sketchybar-reload" ''
  #   # SDKROOT="$(xcrun --show-sdk-path)"
  #   swift ${./sketchybarReload.swift}
  # '';
in
{
  config = {
    home = {
      packages = [ pkgs.pkgs-bleeding.sketchybar ];

      file = {
        ".config/sketchybar/sketchybarrc".source = mkSketchybarScript "sketchybarrc" ./sketchybarrc.nu;
        ".config/sketchybar/plugins/battery.nu".source = mkSketchybarScript "battery" ./plugins/battery.nu;
        ".config/sketchybar/plugins/clock.nu".source = mkSketchybarScript "clock" ./plugins/clock.nu;
        ".config/sketchybar/plugins/front_app.nu".source =
          mkSketchybarScript "front_app" ./plugins/front_app.nu;
        ".config/sketchybar/plugins/space.nu".source = mkSketchybarScript "space" ./plugins/space.nu;
        ".config/sketchybar/plugins/volume.nu".source = mkSketchybarScript "volume" ./plugins/volume.nu;
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

    # # reload sketchybar on screen off/on
    # # https://github.com/FelixKratz/SketchyBar/issues/512#issuecomment-2560079227
    # launchd.agents.sketchybarReload = {
    #   enable = true;
    #   config = {
    #     Debug = true;
    #     Program = "${sketchybarReload}";
    #     KeepAlive = true;
    #     RunAtLoad = true;
    #     StandardOutPath = "/tmp/sketchybarReload.log";
    #     StandardErrorPath = "/tmp/sketchybarReload.err";
    #   };
    # };
  };
}
