{ config, inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ../../lib/common/sops.nix
  ];

  config = {
    sops.secrets."git/allowed_signers" = {
      owner = config.defaultUser;
      mode = "0444";
    };
  };
}
