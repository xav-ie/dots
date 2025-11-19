{
  writeNuApplication,
  fzf,
  jq,
  nix,
  stdenv,
}:
writeNuApplication {
  name = "searcher";
  runtimeInputs = [
    fzf
    jq
    nix
  ];
  text = builtins.replaceStrings [ "\${stdenv.hostPlatform.system}" ] [ stdenv.hostPlatform.system ] (
    builtins.readFile ./searcher.nu
  );
}
