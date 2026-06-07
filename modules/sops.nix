# sops-nix wiring (NixOS + darwin); secrets defined in ./_lib/sops-common.nix.
{ inputs, ... }:
let
  sopsCommon = ./_lib/sops-common.nix;
in
{
  flake.modules.nixos.linux = {
    imports = [
      inputs.sops-nix.nixosModules.sops
      sopsCommon
    ];
  };
  flake.modules.darwin.macos = {
    imports = [
      inputs.sops-nix.darwinModules.sops
      sopsCommon
    ];
  };
}
