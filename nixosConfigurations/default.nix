{ inputs, ... }:
# TODO: refactor
let
  user = "x";
  # systems = builtins.attrNames inputs.systems;
  # system = builtins.elem "x86_64-linux" systems;
  system = "x86_64-linux";
  # TODO: fix
  configurations = {
    # custom desktop tower
    praesidium = inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs user system;
      };
      modules = [
        ../common
        ./hosts/praesidium
        ./linux-home-manager.nix
        {
          # TODO: enable on a per-package basis
          config.nixpkgs.config.allowUnfree = true;
        }
      ];
    };
  };
in
configurations
