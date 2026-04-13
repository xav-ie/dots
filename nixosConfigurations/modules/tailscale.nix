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
}
