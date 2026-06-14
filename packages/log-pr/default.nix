{
  gh,
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "log-pr";
  runtimeInputs = [
    gh
    git
  ];
  text = ./log-pr.nu |> builtins.readFile;
}
