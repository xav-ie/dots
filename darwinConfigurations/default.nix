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
