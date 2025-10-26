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
  text = builtins.readFile ./log-pr.nu;
}
