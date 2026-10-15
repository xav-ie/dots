{
  flake.modules.homeManager.linux =
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
        whisper-cpp = pkgs.pkgs-bleeding-cuda.whisper-cpp;
      };

      model = "large-v3-turbo-q8_0";
      # hyprwhspr-rs only looks in this hardcoded dir and never downloads, so
      # fetch the model on first start instead of carrying it in the closure.
      fetchModel = pkgs.writeShellScript "hyprwhspr-rs-fetch-model" ''
        set -e
        dir="$HOME/.local/share/hyprwhspr-rs/models"
        file="$dir/ggml-${model}.bin"
        [ -s "$file" ] && exit 0
        mkdir -p "$dir"
        ${pkgs.curl}/bin/curl -fL --retry 3 -o "$file.part" \
          "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model}.bin"
        mv "$file.part" "$file"
      '';

      configFile = pkgs.writeText "hyprwhspr-rs-config.jsonc" (
        {
          shortcuts = {
            hold = "${cfg.pushToTalk.modifier}+${cfg.pushToTalk.key}";
          };
          audio_feedback = true;
          start_sound_volume = 0.1;
          stop_sound_volume = 0.1;
          auto_copy_clipboard = false;
          shift_paste = true;
          fast_vad = {
            enabled = true;
            profile = "aggressive";
          };
          transcription = {
            provider = "whisper_cpp";
            whisper_cpp = {
              inherit model;
              threads = 4;
              gpu_layers = 999;
              prompt = "Transcribe as technical documentation with proper capitalization, acronyms, and technical terminology. Do not add punctuation.";
            };
          };
        }
        |> builtins.toJSON
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
          (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            wayland.windowManager.hyprland.settings = {
              # Consume SUPER+G so it doesn't pass through to the focused window
              bind = [
                {
                  _args = [
                    cfg.pushToTalk.hyprlandKeys
                    (lib.generators.mkLuaInline "hl.dsp.no_op()")
                  ];
                }
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
                ExecStartPre = fetchModel;
                # The first start downloads ~870 MB.
                TimeoutStartSec = "15min";
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
    };
}
