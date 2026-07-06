# Server-safe essentials (nix, sops, tailscale, openssh, systemd, nix-ld, nh)
# live in `flake.modules.nixos.base`. `linux` imports base and layers desktop
# services on top; headless hosts (arca) import base directly.
{ config, ... }:
{
  flake.modules.nixos.linux.imports = [ config.flake.modules.nixos.base ];
}
