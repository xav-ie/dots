# arca — headless Hetzner Cloud VPS (x86_64-linux) running the `atticd` Nix
# binary cache. First server host in this repo: imports the lean `base` set, not
# the desktop-laden `linux`, and has no home-manager — so its closure skips the
# GUI/ML tooling praesidium carries.
{ config, inputs, ... }:
let
  flakeModules = config.flake.modules;
in
{
  configurations.nixos.arca.module = {
    imports = [
      flakeModules.nixos.common
      flakeModules.nixos.base
      inputs.disko.nixosModules.disko
      ./_arca-body.nix
    ];

    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
