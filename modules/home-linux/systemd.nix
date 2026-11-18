{
  flake.modules.homeManager.linux =
    { lib, pkgs, ... }:
    let
      check-systemd-units = pkgs.writeNuApplication {
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
                                   (systemctl --user show --property=LoadState --value $unit
                                   | str trim) == 'bad-setting'
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
      };

      kill-spyware = pkgs.writeNuApplication {
        name = "kill-spyware";
        runtimeInputs = with pkgs; [
          pkgs-mine.notify
          pkgs-mine.openrgb-appimage
          hyprland
          zenity
        ];
        text = # nu
          ''
            notify "Time to log off" "Work is done for today." --icon evening --expire 12hr
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
      };

      # Claims the work morning on my first return to either machine: hypridle's
      # seat-back here, Notifier's wake hook on nox (over ssh). Exit 0 means this
      # caller won the claim and shows Good morning; 1 means already claimed
      # today, 2 means not a work morning (weekends, before 05:00, after 17:00).
      start-work = pkgs.writeNuApplication {
        name = "start-work";
        runtimeInputs = with pkgs.pkgs-mine; [ openrgb-appimage ];
        text = # nu
          ''
            def main [] {
              let now = date now
              let weekday = $now | format date "%u" | into int
              let hour = $now | format date "%H" | into int
              if $weekday > 5 or $hour < 5 or $hour >= 17 { exit 2 }
              let state = $env.XDG_STATE_HOME? | default ($env.HOME | path join .local/state) | path join start-work
              let today = $now | format date "%F"
              if (try { open $state | str trim } catch { "" }) == $today { exit 1 }
              mkdir ($state | path dirname)
              $today | save -f $state
              try { openrgb -p purple | ignore }
            }
          '';
      };

      good-morning = pkgs.writeNuApplication {
        name = "good-morning";
        runtimeInputs = [
          pkgs.pkgs-mine.notify
          start-work
        ];
        text = # nu
          ''
            if (start-work | complete | get exit_code) == 0 {
              notify "Good morning" "Time to start work!" --icon morning --expire 12hr
            }
          '';
      };
    in
    {
      config = {
        # nox's Notifier runs start-work over ssh on wake.
        home.packages = [ start-work ];

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
              ExecStart = "${check-systemd-units}/bin/check-systemd-units";
            };
            Install = {
              WantedBy = [ "default.target" ];
            };
          };

          # Started by hypridle when I return to the seat.
          services.good-morning = {
            Unit.Description = "Greet the first return of the work morning";
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe good-morning;
            };
          };

          # Zoom loves to "helpfully" stay open even when I kill through UI
          services.kill-spyware = {
            Unit = {
              Description = "Stop spyware";
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${kill-spyware}/bin/kill-spyware";
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

        };
      };
    };
}
