{ inputs, ... }:
{
  imports = [
    inputs.sops-nix.darwinModules.sops
    ../../lib/common/sops.nix
  ];
}
