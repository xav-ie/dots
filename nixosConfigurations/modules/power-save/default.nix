{
  config,
  lib,
  pkgs,
  ...
}:
let
  power-save-enter = "power-save-enter";
  power-save-exit = "power-save-exit";
  power-save-enter-delayed = "power-save-enter-delayed";
  logind-power-monitor = "logind-power-monitor";
in
{
  config = {
    # CPU power management with SSH-aware boosting
    # Boots at full performance, only limits when explicitly triggered by idle timeout

    # Service to enter power save mode (hardware minimum) - checks if SSH is active first
    systemd.services.${power-save-enter} = {
      description = "Enter power save mode (limit CPU and GPU to minimum)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeNuApplication {
            name = power-save-enter;
            runtimeInputs = [
              pkgs.pkgs-mine.is-sshed
              config.boot.kernelPackages.nvidiaPackages.production
            ];
            text = # nu
              ''
                # Limit CPU to hardware minimum
                let min_perf = (open /sys/devices/system/cpu/intel_pstate/min_perf_pct | str trim)
                $min_perf | save -f /sys/devices/system/cpu/intel_pstate/max_perf_pct
                print $"CPU: Set to ($min_perf)% - hardware minimum"

                # Limit GPU to hardware minimum (graceful if driver mismatch)
                try {
                  let gpu_min = (nvidia-smi --query-gpu=power.min_limit --format=csv,noheader,nounits | str trim)
                  nvidia-smi -pl $gpu_min
                  print $"GPU: Set to ($gpu_min)W - hardware minimum"
                } catch {
                  print "GPU: Skipped - driver mismatch (reboot required)"
                }
              '';
          }
        );
      };
    };

    # Service to enter power save after delay (for SSH grace period)
    systemd.services.${power-save-enter-delayed} = {
      description = "Wait 30min then enter power save mode";
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe (
          pkgs.writeNuApplication {
            name = power-save-enter-delayed;
            runtimeInputs = [ pkgs.systemd ];
            text = # nu
              ''
                # Wait 30 minutes
                sleep 30min
                # Then try to enter power save (will check if SSH reconnected)
                systemctl start ${power-save-enter}.service
              '';
          }
        );
      };
    };

    # Service to exit power save mode (100% CPU, full GPU)
    systemd.services.${power-save-exit} = {
      description = "Exit power save mode (restore CPU and GPU to full)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeNuApplication {
            name = power-save-exit;
            runtimeInputs = [
              pkgs.systemd
              config.boot.kernelPackages.nvidiaPackages.production
            ];
            text = # nu
              ''
                # Cancel any pending delayed power save
                systemctl stop ${power-save-enter-delayed}.service

                # Restore full CPU performance
                "100" | save -f /sys/devices/system/cpu/intel_pstate/max_perf_pct
                print "CPU: Restored to 100%"

                # Restore GPU to default power limit (graceful if driver mismatch)
                try {
                  let gpu_default = (nvidia-smi --query-gpu=power.default_limit --format=csv,noheader,nounits | str trim)
                  nvidia-smi -pl $gpu_default
                  print $"GPU: Restored to ($gpu_default)W - default limit"
                } catch {
                  print "GPU: Skipped - driver mismatch (reboot required)"
                }
              '';
          }
        );
      };
    };

    # Monitor logind for session changes and manage power save accordingly
    systemd.services.${logind-power-monitor} = {
      description = "Monitor logind session changes and manage power save state";
      documentation = [
        "man:loginctl(1)"
        "man:busctl(1)"
      ];
      after = [ "systemd-logind.service" ];
      requires = [ "systemd-logind.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = logind-power-monitor;
        ExecStart = lib.getExe (
          pkgs.writeNuApplication {
            name = logind-power-monitor;
            runtimeInputs = [
              pkgs.systemd
              pkgs.pkgs-mine.is-sshed
            ];
            text = builtins.readFile ./logind-power-monitor.nu;
          }
        );
      };
    };

    # Ensure power saving features are enabled
    powerManagement = {
      enable = true;
      cpuFreqGovernor = "powersave";
    };

    # Allow user to start power save services without password
    security.polkit.extraConfig = # js
      ''
        polkit.addRule(function(action, subject) {
          if ((action.id == "org.freedesktop.systemd1.manage-units" &&
               (action.lookup("unit") == "${power-save-enter}.service" ||
                action.lookup("unit") == "${power-save-enter-delayed}.service" ||
                action.lookup("unit") == "${power-save-exit}.service")) &&
              subject.user == "${config.defaultUser}") {
            return polkit.Result.YES;
          }
        });
      '';

  };
}
