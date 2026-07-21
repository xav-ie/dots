{
  gh,
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "git-log-pr";
  runtimeInputs = [
    gh
    git
  ];
  text = ./git-log-pr.nu |> builtins.readFile;
}
