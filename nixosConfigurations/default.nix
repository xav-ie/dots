{ lib, inputs, ... }@toplevel:
# TODO: refactor to do this a better way?
let
  hasSystem = system: builtins.elem system (import inputs.systems);
  addSystem = system: systemConfig: lib.attrsets.optionalAttrs (hasSystem system) systemConfig;
  system = "x86_64-linux";
  configurations =
    { }
    // addSystem system {
      # custom desktop tower
      praesidium = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs system toplevel;
        };
        modules = [
          ../lib/common
          ./hosts/praesidium
          ./linux-home-manager.nix
          {
            # TODO: enable on a per-package basis
            config.nixpkgs.config.allowUnfree = true;
          }
          inputs.sops-nix.nixosModules.sops
        ];
      };
    };
in
configurations
