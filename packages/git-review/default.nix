{
  writeNuApplication,
  git,
  gh,
}:
writeNuApplication {
  name = "git-review";
  runtimeInputs = [
    git
    gh
  ];
  text = ./git-review.nu |> builtins.readFile;
}
