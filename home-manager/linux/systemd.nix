{ lib, pkgs, ... }:
let
  writeNuApplication = import ../../lib/writeNuApplication { inherit lib pkgs; };
in
{
  config = {
    systemd.user = {
      # Nicely reload system units when changing configs
      startServices = "sd-switch";

      services.ollama-server = {
        Unit = {
          Description = "Run ollama server";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
        Service = {
          ExecStart = "${pkgs.ollama}/bin/ollama serve";
        };
      };

      # Zoom loves to "helpfully" stay open even when I kill through UI
      services.kill-spyware = {
        Unit = {
          Description = "Stop spyware";
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe (writeNuApplication {
            name = "kill-spyware";
            runtimeInputs = with pkgs; [
              libnotify
              hyprland
              zenity
            ];
            text = # nu
              ''
                notify-send "Work is done. Time to log off..."
                let zoom_window_client = (hyprctl clients -j
                                          | from json
                                          | filter {|| $in.title == "Zoom" })
                if ($zoom_window_client | length) == 1 {
                  try {
                    zenity --question --text="Close Zoom?"; kill ($zoom_window_client | first | get pid)
                  } catch {
                    notify-send "No (or more than one) zoom windows found."
                  }
                }
              '';
          });
        };
      };
      timers.kill-spyware = {
        Unit = {
          Description = "Stop spyware after working hours";
        };
        Timer = {
          Unit = "kill-spyware.service";
          OnCalendar = "Mon..Fri 18:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };

      services.start-work = {
        Unit = {
          Description = "Start work programs";
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "start-work";
              runtimeInputs = with pkgs; [
                libnotify
              ];
              text = ''
                notify-send "Good morning, time to start work!"
              '';
            }
          );
        };
      };
      timers.start-work = {
        Unit = {
          Description = "Start work programs every weekday at 9am";
        };
        Timer = {
          Unit = "start-work.service";
          OnCalendar = "Mon..Fri 09:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
