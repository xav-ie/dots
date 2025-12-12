{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscale-status = pkgs.writeNuApplication {
    name = "tailscale-status";
    runtimeInputs = [ pkgs.tailscale ];
    text = # nu
      ''
        if ((tailscale status -json | from json | get BackendState) == "Running") {
          print -e "Tailscale running."
        } else {
          print -e $"(ansi red)  Tailscale not running.(ansi reset)"
          tailscale status | tee { print -e }
        }
      '';
  };
in
{
  config = {
    environment.systemPackages = [ pkgs.tailscale ];

    services.tailscale.enable = true;

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    system.activationScripts.tailscaleStatus = ''
      ${lib.getExe tailscale-status}
    '';
  };
}
