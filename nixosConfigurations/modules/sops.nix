{ inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ../../lib/common/sops.nix
  ];
}
