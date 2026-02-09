_: {
  imports = [
    ../../lib/common
    ./boot-args.nix
    ./certs.nix
    ./darwin-home-manager.nix
    ./defaults-optimization
    ./dnsmasq.nix
    ./homebrew-cache.nix
    # ./linux-builder.nix  # Disabled: using praesidium as remote builder instead
    ./nix-homebrew.nix
    ./openssh.nix
    ./orca-slicer.nix
    ./pam-reattach.nix
    ./remote-builder.nix
    ./reverse-proxy.nix
    ./settings.nix
    ./sops.nix
    ./tailscale.nix
  ];
}
