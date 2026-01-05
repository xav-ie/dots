{ lib, pkgs, ... }:
{
  config = {
    systemd.user.services.tailscale-status = {
      Unit = {
        Description = "Check Tailscale status";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeNuApplication {
            name = "tailscale-status";
            runtimeInputs = [
              pkgs.tailscale
              pkgs.pkgs-mine.notify
            ];
            text = # nu
              ''
                # Wait up to 30 seconds for tailscale to be running
                mut state = ""
                for i in 1..30 {
                  $state = (tailscale status -json | from json | get BackendState)
                  if $state == "Running" {
                    print -e $"Tailscale running, took ($i)s."
                    return
                  }
                  print -e $"Attempt ($i): state=($state), waiting..."
                  sleep 1sec
                }
                # Timeout - notify failure
                print -e $"Tailscale not running after 30s: ($state)"
                notify $"Tailscale not running: ($state)"
                exit 1
              '';
          }
        );
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
