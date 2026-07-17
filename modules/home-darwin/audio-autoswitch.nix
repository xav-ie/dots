# Auto-select USB-C EarPods as the default output when plugged in — macOS won't
# for USB audio devices. Runs packages/audio-autoswitch as a KeepAlive agent.
_: {
  flake.modules.darwin.macos =
    { pkgs, ... }:
    {
      launchd.user.agents.audio-autoswitch.serviceConfig = {
        ProgramArguments = [ "${pkgs.pkgs-mine.audio-autoswitch}/bin/audio-autoswitch" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/audio-autoswitch.out.log";
        StandardErrorPath = "/tmp/audio-autoswitch.err.log";
      };
    };
}
