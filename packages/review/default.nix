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
  text = builtins.readFile ./review.nu;
}
