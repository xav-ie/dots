{ ... }:
{
  imports = [
    ../../lib/common
    ./atop
    ./bluetooth.nix
    ./ccache.nix
    ./cloudflared.nix
    ./dnsmasq.nix
    ./hardware-configuration.nix
    ./home-assistant.nix
    ./hyprland.nix
    ./jellyfin.nix
    ./lightrag.nix
    ./linux-home-manager.nix
    ./n8n.nix
    ./nginx.nix
    ./nix-config.nix
    ./noisetorch
    ./plover.nix
    ./podman.nix
    ./portainer.nix
    ./postiz.nix
    ./power-save
    ./quadlet.nix
    ./quartz.nix
    ./remote-builder.nix
    ./sops.nix
    ./spdf.nix
    ./sudo-askpass.nix
    ./systemd.nix
    ./tailscale.nix
    ./traefik.nix
    ./udisks.nix
    ./uptime-kuma.nix
    # not currently routing correctly...
    # ./twingate.nix
  ];

  config = {
    services.reverse-proxy.enable = false;
  };
}
