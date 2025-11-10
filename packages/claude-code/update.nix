{
  writeNuApplication,
  curl,
  nix,
}:
writeNuApplication {
  name = "claude-code-update";
  runtimeInputs = [
    curl
    nix
  ];
  text = builtins.readFile ./update.nu;
}
