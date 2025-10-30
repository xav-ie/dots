{ ... }:
{
  imports = [
    ../../lib/common
    ./atop
    ./bluetooth.nix
    ./dnsmasq.nix
    ./hardware-configuration.nix
    ./home-assistant.nix
    ./hyprland.nix
    ./linux-home-manager.nix
    ./nginx.nix
    ./nix-config.nix
    ./noisetorch.nix
    ./plover.nix
    ./podman.nix
    ./portainer.nix
    ./postiz.nix
    ./quadlet.nix
    ./sops.nix
    ./spdf.nix
    ./systemd.nix
    ./tailscale.nix
    ./traefik.nix
    ./udisks.nix
    # not currently routing correctly...
    # ./twingate.nix
  ];

  config = {
    services.reverse-proxy.enable = false;
  };
}
