{ pkgs, ... }:
{
  config = {
    systemd.user = {
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

      # Zoom and Slack love to "helpfully" stay open even when I kill them through UI
      services.kill-spyware = {
        Unit = {
          Description = "Stop spyware";
        };
        Service = {
          Type = "oneshot";
          ExecStart = ../dotfiles/kill-spyware.sh;
          # TODO: I guess you need this? :/
          Environment = "PATH=/run/current-system/sw/bin";
        };
      };

      # Nicely reload system units when changing configs
      startServices = "sd-switch";

      timers.kill-spyware = {
        Unit = {
          Description = "Stop spyware after working hours";
        };
        Timer = {
          Unit = "kill-spyware.service";
          OnCalendar = "18:00";
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
          ExecStart = ../dotfiles/start-work.sh;
          Environment = "PATH=/run/current-system/sw/bin";
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
