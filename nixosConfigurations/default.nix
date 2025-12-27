{ lib, inputs, ... }@toplevel:
let
  supportedSystems = import inputs.systems;
  hasSystem = system: builtins.elem system supportedSystems;
in
lib.optionalAttrs (hasSystem "x86_64-linux") {
  # custom desktop tower
  praesidium = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs toplevel;
    };
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      ./hosts/praesidium
      inputs.virtual-headset.nixosModules.default
    ];
  };
}
