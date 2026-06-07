# praesidium — desktop tower (x86_64-linux, NVIDIA).
{ config, inputs, ... }:
let
  flakeModules = config.flake.modules;
in
{
  configurations.nixos.praesidium.module =
    { config, ... }:
    {
      imports = [
        flakeModules.nixos.common
        flakeModules.nixos.linux
        flakeModules.nixos.praesidium
        inputs.hardware.nixosModules.common-cpu-intel-cpu-only
        inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
        inputs.hardware.nixosModules.common-pc-ssd
        inputs.virtual-headset.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ./_praesidium-body.nix
      ];

      nixpkgs.hostPlatform = "x86_64-linux";

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        users.${config.defaultUser} = {
          imports = [
            flakeModules.homeManager.common
            flakeModules.homeManager.linux
          ];
          # Pin to the home-manager release this host was first set up on.
          home.stateVersion = "23.11";
        };
      };
    };
}
