# mic-denoise: RNNoise virtual mic agent (packages/mic-denoise), opened from the
# sketchybar `mic_denoise` item. Runs straight from the store .app; the
# Microphone grant pins that bundle's cdhash, and ffmpeg inherits it as a child.
# MIC_DENOISE_PKG flips the launchd config hash so it restarts on code changes.
_: {
  flake.modules.darwin.macos =
    { pkgs, ... }:
    {
      launchd.user.agents.mic-denoise.serviceConfig = {
        ProgramArguments = [
          "${pkgs.pkgs-mine.mic-denoise}/Applications/mic-denoise.app/Contents/MacOS/mic-denoise"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.MIC_DENOISE_PKG = "${pkgs.pkgs-mine.mic-denoise}";
        StandardOutPath = "/tmp/mic-denoise.out.log";
        StandardErrorPath = "/tmp/mic-denoise.err.log";
      };

      security.tcc.apps = [
        {
          bundleId = "com.x.mic-denoise";
          appPath = "${pkgs.pkgs-mine.mic-denoise}/Applications/mic-denoise.app";
          pin = "cdhash";
          services = [ "Microphone" ];
          reloadAgent = "mic-denoise";
        }
      ];
    };
}
