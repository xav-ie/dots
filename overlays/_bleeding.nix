# Canonical constructor for the nixpkgs-bleeding package set, shared by
# overlays/default.nix's `mkBleeding`, flake/packages.nix and flake/devshell.nix
# so they all import it with the same config.
{
  nixpkgs-bleeding,
  system,
  config ? { },
  overlays ? [ ],
}:
import nixpkgs-bleeding {
  inherit system;
  config = {
    allowUnfree = true;
  }
  // config;
  inherit overlays;
}
