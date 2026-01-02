# Cross-platform scheduled services module
# Generates systemd timers (Linux) and launchd agents (macOS) from a single definition
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.scheduled;

  scheduledServiceOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable this scheduled service.";
        };

        description = lib.mkOption {
          type = lib.types.str;
          default = "Scheduled service: ${name}";
          description = "Description of the service.";
        };

        command = lib.mkOption {
          type = lib.types.str;
          description = "Command to execute.";
        };

        workingDirectory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Working directory for the command.";
        };

        calendar = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = ''
            Schedule in systemd OnCalendar format.
            Common values: "daily", "hourly", "weekly", or custom like "*-*-* 09:00:00".
          '';
        };

        hour = lib.mkOption {
          type = lib.types.int;
          default = 9;
          description = "Hour to run (0-23). Used for launchd on macOS.";
        };

        minute = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Minute to run (0-59). Used for launchd on macOS.";
        };

        randomDelay = lib.mkOption {
          type = lib.types.str;
          default = "1h";
          description = "Random delay to add (Linux only). Helps avoid thundering herd.";
        };

        persistent = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run immediately if a scheduled run was missed (Linux only).";
        };
      };
    };

  enabledServices = lib.filterAttrs (_: svc: svc.enable) cfg;

  # Convert calendar string to launchd StartCalendarInterval
  mkLaunchdInterval =
    svc:
    if svc.calendar == "hourly" then
      [ { Minute = svc.minute; } ]
    else if svc.calendar == "weekly" then
      [
        {
          Weekday = 0;
          Hour = svc.hour;
          Minute = svc.minute;
        }
      ]
    else
      # daily or custom - default to hour/minute
      [
        {
          Hour = svc.hour;
          Minute = svc.minute;
        }
      ];

in
{
  options.services.scheduled = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule scheduledServiceOpts);
    default = { };
    description = "Cross-platform scheduled services (systemd timers on Linux, launchd agents on macOS).";
  };

  config = lib.mkIf (enabledServices != { }) {
    # Linux - systemd user services and timers
    systemd.user.services = lib.mkIf pkgs.stdenv.isLinux (
      lib.mapAttrs (_name: svc: {
        Unit.Description = svc.description;
        Service = {
          Type = "oneshot";
          ExecStart = svc.command;
        }
        // lib.optionalAttrs (svc.workingDirectory != null) {
          WorkingDirectory = svc.workingDirectory;
        };
      }) enabledServices
    );

    systemd.user.timers = lib.mkIf pkgs.stdenv.isLinux (
      lib.mapAttrs (_name: svc: {
        Unit.Description = "${svc.description} timer";
        Timer = {
          OnCalendar = svc.calendar;
          Persistent = svc.persistent;
          RandomizedDelaySec = svc.randomDelay;
        };
        Install.WantedBy = [ "timers.target" ];
      }) enabledServices
    );

    # macOS - launchd agents
    launchd.agents = lib.mkIf pkgs.stdenv.isDarwin (
      lib.mapAttrs (name: svc: {
        enable = true;
        config = {
          Label = "com.user.${name}";
          ProgramArguments = [ svc.command ];
          StartCalendarInterval = mkLaunchdInterval svc;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
        }
        // lib.optionalAttrs (svc.workingDirectory != null) {
          WorkingDirectory = svc.workingDirectory;
        };
      }) enabledServices
    );
  };
}
