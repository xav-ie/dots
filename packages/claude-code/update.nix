{
  writeNuApplication,
  curl,
  nix,
  gnutar,
  nodejs,
}:
writeNuApplication {
  name = "claude-code-update";
  runtimeInputs = [
    curl
    nix
    gnutar
    nodejs
  ];
  text = ./update.nu |> builtins.readFile;
}
