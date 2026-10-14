# Canonical constructor for the nixpkgs-bleeding package set.
#
# EVERY consumer of nixpkgs-bleeding goes through this (or, while bleeding
# shares the main rev, through the main set carrying the same _bleeding-pins.nix)
# — overlays/default.nix's
# `mkBleeding` (→ home-manager's `pkgs.pkgs-bleeding` + the CUDA variant),
# flake/packages.nix (→ nu_plugin_prompt's build),
# and flake/devshell.nix (→ the direnv `nix develop` nu). Pinning here rather
# than at each call site is what keeps them from drifting onto different nushell
# builds, which breaks the plugin protocol handshake across a minor mismatch.
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
  overlays = [ (import ./_bleeding-pins.nix) ] ++ overlays;
}
