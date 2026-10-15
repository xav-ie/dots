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

      hyprwhspr-rs = pkgs.pkgs-bleeding.hyprwhspr-rs.overrideAttrs (old: {
        # Upstream sends the hyprlang `dispatch sendshortcut` form, which the
        # Lua config rejects, so the paste keypress never reaches the window.
        patches = (old.patches or [ ]) ++ [ ./hyprwhspr-lua-sendshortcut.patch ];
      });

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
          # scribe (praesidium's always-loaded parakeet ASR) via its OpenAI-style
          # endpoint, boosted with the meeting vocabulary.
          transcription = {
            provider = "custom.scribe";
            custom.scribe = {
              endpoint = "https://scribe.lalala.casa/v1/audio/transcriptions";
              model = "parakeet-unified-en-0.6b";
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
