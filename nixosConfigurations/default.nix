{ inputs, ... }:
# TODO: refactor
let
  user = "x";
  systems = builtins.attrNames inputs.systems;
  system = builtins.elem "x86_64-linux" systems;
  configurations =
    if system then
      {
        # custom desktop tower
        praesidium = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs user system;
          };
          modules = [
            ../common
            ./hosts/praesidium
            ./linux-home-manager.nix
          ];
        };
      }
    else
      { };
in
configurations
