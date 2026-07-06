# sops-nix wiring (NixOS + darwin).
{ inputs, ... }:
let
  sopsCommon = ./_lib/sops-common.nix;
in
{
  # The sops module on every NixOS host. sops-nix derives an age identity from
  # the host's SSH ed25519 key, so a host can decrypt secrets encrypted to its
  # own key with no key file.
  flake.modules.nixos.base.imports = [ inputs.sops-nix.nixosModules.sops ];

  # The personal master key and all personal secret declarations live only on the
  # interactive hosts (`linux`, `darwin.macos`). Servers like arca skip these:
  # they hold their own host-scoped key and per-host secrets file, so a public box
  # never carries the master key nor materialises unrelated secrets.
  flake.modules.nixos.linux.imports = [ sopsCommon ];

  flake.modules.darwin.macos.imports = [
    inputs.sops-nix.darwinModules.sops
    sopsCommon
  ];
}
