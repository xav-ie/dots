{ inputs, ... }@toplevel:
let
  system = "aarch64-darwin";
  inherit (inputs.nix-darwin.lib) darwinSystem;
in
{
  # macbook air - m3
  nox = darwinSystem {
    inherit system;
    specialArgs = {
      inherit inputs toplevel;
    };
    modules = [
      ./hosts/nox
      ./modules
      ./modules/boot-args.nix
      ./modules/certs.nix
      ./modules/darwin-home-manager.nix
      ./modules/dnsmasq.nix
      # ./modules/linux-builder.nix  # Disabled: using praesidium as remote builder instead
      ./modules/openssh.nix
      ./modules/remote-builder.nix
      ./modules/nix-homebrew.nix
      ./modules/pam-reattach.nix
      ./modules/reverse-proxy.nix
      ./modules/settings.nix
      ./modules/sops.nix
      ./modules/tailscale.nix
    ];
  };
}
