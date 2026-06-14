{
  writeNuApplication,
  nix,
  nix-output-monitor,
}:
writeNuApplication {
  name = "nom-run";
  runtimeInputs = [
    nix
    nix-output-monitor
  ];
  text = ./nom-run.nu |> builtins.readFile;
}
