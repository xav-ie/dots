{ inputs, ... }@toplevel:
let
  user = "x";
  system = "aarch64-darwin";
  inherit (inputs.nix-darwin.lib) darwinSystem;
in
{
  # macbook air - m1
  castra = darwinSystem {
    inherit system;
    specialArgs = {
      inherit inputs user toplevel;
    };
    modules = [
      ../lib/common
      ./darwin-home-manager.nix
      ./hosts/castra
    ];
  };

  # macbook air - m3
  stella = darwinSystem {
    inherit system;
    specialArgs = {
      inherit inputs user toplevel;
    };
    modules = [
      ../lib/common
      ./darwin-home-manager.nix
      ./hosts/stella
      ./nix-homebrew.nix
      # {
      #   nix.settings.trusted-users = [ user ];
      #   nix.linux-builder.enable = true;
      # }
    ];
  };
}
