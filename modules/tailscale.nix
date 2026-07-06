# Tailscale on every Linux host (via `base`) and on macOS.
{
  flake.modules.nixos.base =
    {
      config,
      pkgs,
      ...
    }:
    {
      config = {
        environment.systemPackages = [ pkgs.tailscale ];

        services.tailscale = {
          enable = true;
          extraSetFlags = [ "--accept-dns=false" ];
        };

        networking.firewall = {
          trustedInterfaces = [ "tailscale0" ];
          allowedUDPPorts = [ config.services.tailscale.port ];
        };
      };
    };

  flake.modules.darwin.macos = {
    services.tailscale.enable = true;
  };
}
