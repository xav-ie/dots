{
  writeNuApplication,
  fzf,
  jq,
  nix,
  system,
}:
writeNuApplication {
  name = "searcher";
  runtimeInputs = [
    fzf
    jq
    nix
    system
  ];
  text = builtins.readFile ./searcher.nu;
}
