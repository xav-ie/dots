{ lib, inputs, ... }@toplevel:
# TODO: refactor
let
  user = "x";
  hasSystem = system: builtins.elem system (import inputs.systems);
  addSystem = system: systemConfig: lib.attrsets.optionalAttrs (hasSystem system) systemConfig;
  system = "x86_64-linux";
  # TODO: do this a better way?
  configurations =
    { }
    // addSystem system {
      # custom desktop tower
      praesidium = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            inputs
            system
            toplevel
            user
            ;
        };
        modules = [
          ../lib/common
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
