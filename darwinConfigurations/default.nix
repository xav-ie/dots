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
      ./modules
      ./modules/certs.nix
      ./modules/darwin-home-manager.nix
      ./modules/dnsmasq.nix
      # ./modules/linux-builder.nix  # Disabled: using praesidium as remote builder instead
      ./modules/remote-builder.nix
      ./modules/nix-homebrew.nix
      ./modules/pam-reattach.nix
      ./modules/reverse-proxy.nix
      ./modules/settings.nix
      ./modules/sops.nix
    ];
  };
}
