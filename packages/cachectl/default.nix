{
  writeNuApplication,
  sops,
  openssh,
  gh,
  nix,
  nixos-rebuild,
}:
writeNuApplication {
  name = "cachectl";
  runtimeInputs = [
    sops
    openssh
    gh
    nix
    nixos-rebuild
  ];
  text = builtins.readFile ./cachectl.nu;
}
