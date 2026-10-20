{
  # Desktop voice satellite: wake word on the default PipeWire mic, replies and
  # timer alarms on the default speakers. Home Assistant adds it through the
  # ESPHome integration at 127.0.0.1:6053.
  flake.modules.nixos.praesidium =
    { config, pkgs, ... }:
    let
      # "Computer"/"Computah" (openWakeWord), from the MIT-licensed community collection.
      computer = pkgs.runCommand "wake-word-computer" { } ''
        mkdir $out
        cp ${
          pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/computer/computer_v2.tflite";
            hash = "sha256-QR2zZJVb97ehOlDXMqi1nBKeL74TClT56zwgyhg7xNA=";
          }
        } $out/computer.tflite
        cat > $out/computer.json <<'JSON'
        {
          "type": "openWakeWord",
          "wake_word": "Computah",
          "model": "computer.tflite",
          "openWakeWord": { "probability_cutoff": 0.7 }
        }
        JSON
      '';
    in
    {
      systemd.user.services.linux-voice-assistant = {
        description = "Home Assistant voice satellite";
        wantedBy = [ "default.target" ];
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        # Its mic stream dies with PipeWire and never recovers, so restart along with it.
        partOf = [ "pipewire.service" ];
        unitConfig.ConditionUser = config.defaultUser;
        environment.PYTHONUNBUFFERED = "1";
        serviceConfig = {
          ExecStart = builtins.concatStringsSep " " [
            "${pkgs.pkgs-mine.linux-voice-assistant}/bin/linux-voice-assistant"
            "--name ${config.networking.hostName}"
            "--host 127.0.0.1"
            "--disable-peripheral-api"
            "--wake-word-dir ${computer}"
            "--wake-model computer"
            "--preferences-file %S/linux-voice-assistant/preferences.json"
            "--download-dir %S/linux-voice-assistant/local"
          ];
          StateDirectory = "linux-voice-assistant";
          Restart = "on-failure";
        };
      };
    };
}
