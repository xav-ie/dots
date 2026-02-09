{ inputs, ... }@toplevel:
let
  inherit (inputs.nix-darwin.lib) darwinSystem;
in
{
  # macbook air - m3
  nox = darwinSystem {
    specialArgs = {
      inherit inputs toplevel;
    };
    modules = [
      { nixpkgs.hostPlatform = "aarch64-darwin"; }
      ./hosts/nox
      ./modules
    ];
  };
}
