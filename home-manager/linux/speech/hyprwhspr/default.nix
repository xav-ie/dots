{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.speech;
  enabled = cfg.app == "hyprwhspr";

  hyprwhspr-rs = pkgs.pkgs-bleeding.hyprwhspr-rs.override {
    whisper-cpp = pkgs.pkgs-bleeding.whisper-cpp.override { cudaSupport = true; };
    onnxruntime = pkgs.pkgs-bleeding.onnxruntime.override { cudaSupport = true; };
  };

  configFile = pkgs.writeText "hyprwhspr-rs-config.jsonc" (
    builtins.toJSON {
      shortcuts = {
        hold = "${cfg.pushToTalk.modifier}+${cfg.pushToTalk.key}";
      };
      audio_feedback = true;
      start_sound_volume = 0.1;
      stop_sound_volume = 0.1;
      auto_copy_clipboard = true;
      shift_paste = true;
      fast_vad = {
        enabled = true;
        profile = "aggressive";
      };
      transcription = {
        provider = "whisper_cpp";
        whisper_cpp = {
          model = "large-v3-turbo-q8_0";
          threads = 4;
          gpu_layers = 999;
          prompt = "Transcribe as technical documentation with proper capitalization, acronyms, and technical terminology. Do not add punctuation.";
        };
      };
    }
  );
in
{
  config = lib.mkIf enabled (
    lib.mkMerge [
      {
        home.packages = [
          hyprwhspr-rs
        ];

        xdg.configFile."hyprwhspr-rs/config.jsonc".source = configFile;
      }

      # Linux-only: systemd service + Hyprland keybinding to consume the shortcut
      (lib.mkIf pkgs.stdenv.isLinux {
        wayland.windowManager.hyprland.settings = {
          # Consume SUPER+G so it doesn't pass through to the focused window
          bind = [
            "${cfg.pushToTalk.modifier}, ${cfg.pushToTalk.key}, exec, :"
          ];
        };

        systemd.user.services.hyprwhspr-rs = {
          Unit = {
            Description = "hyprwhspr-rs voice dictation service";
            After = [
              "graphical-session.target"
              "pipewire.service"
            ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${hyprwhspr-rs}/bin/hyprwhspr-rs";
            Restart = "on-failure";
            RestartSec = 3;
            Environment = [ "RUST_LOG=info" ];
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      })
    ]
  );
}
