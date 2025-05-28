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
      ../lib/common
      ./darwin-home-manager.nix
      ./hosts/stella
      ./nix-homebrew.nix
      ./modules/pam-reattach.nix
      ./modules/sops.nix
      # {
      #   nix.settings.trusted-users = [ user ];
      #   nix.linux-builder.enable = true;
      # }
    ];
  };
}
