{
  flake.modules.nixos.praesidium =
    { inputs, ... }:
    {
      imports = [
        inputs.quadlet-nix.nixosModules.quadlet
      ];
    };
}
