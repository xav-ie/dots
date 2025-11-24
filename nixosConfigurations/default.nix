{ lib, inputs, ... }@toplevel:
let
  supportedSystems = import inputs.systems;
  hasSystem = system: builtins.elem system supportedSystems;
  system = "x86_64-linux";
in
lib.optionalAttrs (hasSystem system) {
  # custom desktop tower
  praesidium = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit inputs system toplevel;
    };
    modules = [
      ./hosts/praesidium
      inputs.virtual-headset.nixosModules.default
    ];
  };
}
