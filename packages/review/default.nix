{
  writeNuApplication,
  git,
  gh,
}:
writeNuApplication {
  name = "review";
  runtimeInputs = [
    git
    gh
  ];
  text = ./review.nu |> builtins.readFile;
}
