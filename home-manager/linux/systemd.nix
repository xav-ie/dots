{ lib, pkgs, ... }:
{
  config = {
    systemd.user = {
      # Nicely reload system units when changing configs
      startServices = "sd-switch";

      # Check for bad systemd user unit settings after application
      services.check-systemd-units = {
        Unit = {
          Description = "Check systemd user units for bad settings";
          After = [ "default.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe (
            pkgs.writeNuApplication {
              name = "check-systemd-units";
              runtimeInputs = with pkgs.pkgs-mine; [ notify ];
              text = # nu
                ''
                  let bad_units = (systemctl --user list-unit-files --legend=false
                                   | lines
                                   | split column -r '\s+' unit state preset
                                   | where unit !~ "@\\."
                                   | get unit
                                   | par-each { |unit|
                                     {
                                       unit: $unit,
                                       bad_setting: (
                                         systemctl --user status $unit
                                         | str contains 'bad-setting'
                                       )
                                     }
                                   }
                                   | where bad_setting == true)

                  if ($bad_units | length) > 0 {
                    let bad_units_str = $bad_units | get unit | str join ', '
                    notify $"Bad systemd units found: ($bad_units_str)"
                    error make { msg: $"Bad settings found: ($bad_units)" }
                  } else {
                    print "✓ No bad systemd user units found!"
                  }
                '';
            }
          );
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      services.ollama-server = {
        Unit = {
          Description = "Run ollama server";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.ollama} serve";
        };
      };

      # Zoom loves to "helpfully" stay open even when I kill through UI
      services.kill-spyware = {
        Unit = {
          Description = "Stop spyware";
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe (
            pkgs.writeNuApplication {
              name = "kill-spyware";
              runtimeInputs = with pkgs; [
                pkgs-mine.notify
                pkgs-mine.openrgb-appimage
                hyprland
                zenity
              ];
              text = # nu
                ''
                  notify "Work is done. Time to log off..."
                  let zoom_window_client = (hyprctl clients -j
                                            | from json
                                            | where {|| $in.title == "Zoom" })
                  if ($zoom_window_client | length) == 1 {
                    try {
                      zenity --question --text="Close Zoom?"; kill ($zoom_window_client | first | get pid)
                    } catch {
                      notify "No (or more than one) Zoom windows found."
                    }
                  }
                  openrgb -p off
                '';
            }
          );
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
            pkgs.writeNuApplication {
              name = "start-work";
              runtimeInputs = with pkgs.pkgs-mine; [
                notify
                openrgb-appimage
              ];
              text = # nu
                ''
                  notify "Good morning, time to start work!"
                  openrgb -p purple
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
