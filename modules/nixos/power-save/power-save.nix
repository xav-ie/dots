{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.power-save;

      # Shared scratch dir in tmpfs:
      #   seat-idle        — touched/removed by the user's hypridle (seat demand)
      #   state.json, …    — live snapshot/tallies written by the arbiter
      # World-writable because writers span the root daemon and the user session;
      # it's an ephemeral /run dir. (The arbiter watches traefik's access log for
      # HTTP demand directly, so there's no separate http stamp file any more.)
      stateDir = "/run/power-arbiter";

      power-save-enter-name = "power-save-enter";
      power-save-exit-name = "power-save-exit";
      power-arbiter-name = "power-arbiter";

      # Apply-primitive: pin CPU + GPU to their hardware minimums.
      power-save-enter-pkg = pkgs.writeNuApplication {
        name = power-save-enter-name;
        runtimeInputs = [
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
      };

      # Apply-primitive: restore CPU + GPU to full performance.
      power-save-exit-pkg = pkgs.writeNuApplication {
        name = power-save-exit-name;
        runtimeInputs = [
          config.boot.kernelPackages.nvidiaPackages.production
        ];
        text = # nu
          ''
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
      };

      # Brain + HTTP demand source, merged into one small std-only Rust binary
      # (replaces the two persistent nushell daemons; ~47 MB resident -> ~MBs).
      # It reconciles the enter/exit primitives to `ssh OR seat OR http`, tails
      # traefik's access log itself, and bookkeeps transitions. Inspect with
      # `power-arbiter status`; force with `power-arbiter save|wake|auto`.
      power-arbiter-pkg = pkgs.pkgs-mine.power-arbiter;
    in
    {
      options.services.power-save = {
        enable = lib.mkEnableOption "demand-driven power save (CPU + GPU drop to hardware minimum when no SSH / seat / HTTP demand)";

        httpWakeHosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          # Interactive / on-demand services only. Deliberately excludes the
          # self-refreshing dashboards (hass, portainer, traefik) — a left-open
          # tab there polls on a timer and would pin the box awake 24/7.
          default = [
            "postiz.lalala.casa"
            "social.aztecahome.com"
            "pdf.lalala.casa"
            "executor.lalala.casa"
            "fusion.lalala.casa"
            "chrome.lalala.casa"
            "mcp.lalala.casa"
          ];
          example = [ "postiz.lalala.casa" ];
          description = "Public Host() names whose inbound traefik requests count as demand and wake the machine to full speed. Exact match; pollers like hass/portainer/traefik are intentionally omitted.";
        };

        httpCooldownSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
          description = "Seconds to stay at full speed after the last allowlisted inbound request before the arbiter may re-enter idle.";
        };
      };

      config = lib.mkIf cfg.enable {
        # Ensure power saving features are enabled
        powerManagement = {
          enable = true;
          cpuFreqGovernor = "powersave";
        };

        environment.systemPackages = [ power-arbiter-pkg ];

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0777 root root -"
        ];

        # Service to enter power save mode (hardware minimum)
        systemd.services.${power-save-enter-name} = {
          description = "Enter power save mode (limit CPU and GPU to minimum)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${power-save-enter-pkg}/bin/${power-save-enter-name}";
          };
        };

        # Service to exit power save mode (100% CPU, full GPU)
        systemd.services.${power-save-exit-name} = {
          description = "Exit power save mode (restore CPU and GPU to full)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${power-save-exit-pkg}/bin/${power-save-exit-name}";
          };
        };

        # The brain: one daemon that watches all three demand sources (ssh via
        # is-sshed, seat via hypridle's stamp, http by tailing traefik's access
        # log) and drives the enter/exit units. Persists its history log under
        # StateDirectory (/var/lib/power-arbiter) so it survives reboots.
        systemd.services.${power-arbiter-name} = {
          description = "Reconcile CPU/GPU power state from ssh/seat/http demand";
          after = [
            "systemd-logind.service"
            "traefik.service"
          ];
          wantedBy = [ "multi-user.target" ];
          # is-sshed (demand probe) and systemctl (actuator) on PATH.
          path = [
            pkgs.pkgs-mine.is-sshed
            pkgs.systemd
          ];
          environment = {
            HTTP_COOLDOWN_SECONDS = toString cfg.httpCooldownSeconds;
            ACCESS_LOG = "${config.services.traefik.dataDir}/access.log";
            WAKE_HOSTS = lib.concatStringsSep "," cfg.httpWakeHosts;
          };
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = 5;
            StateDirectory = power-arbiter-name;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = power-arbiter-name;
            ExecStart = "${power-arbiter-pkg}/bin/${power-arbiter-name} daemon";
          };
        };

        # Allow the user's hypridle to poke the system enter/exit units (on
        # idle/resume) without a password prompt.
        security.polkit.extraConfig = # js
          ''
            polkit.addRule(function(action, subject) {
              if ((action.id == "org.freedesktop.systemd1.manage-units" &&
                   (action.lookup("unit") == "${power-save-enter-name}.service" ||
                    action.lookup("unit") == "${power-save-exit-name}.service")) &&
                  subject.user == "${config.defaultUser}") {
                return polkit.Result.YES;
              }
            });
          '';
      };
    };
}
