{
  writeNuApplication,
  sops,
  openssh,
  gh,
  nix,
  nixos-rebuild,
  tailscale,
}:
writeNuApplication {
  name = "cachectl";
  runtimeInputs = [
    sops
    openssh
    gh
    nix
    nixos-rebuild
    tailscale
  ];
  text = builtins.readFile ./cachectl.nu;
}
