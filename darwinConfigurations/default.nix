{ inputs, ... }@toplevel:
let
  system = "aarch64-darwin";
  inherit (inputs.nix-darwin.lib) darwinSystem;
in
{
  # macbook air - m3
  stella = darwinSystem {
    inherit system;
    specialArgs = {
      inherit inputs toplevel;
    };
    modules = [
      ./hosts/stella
    ];
  };
}
