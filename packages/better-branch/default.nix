{
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "better-branch";
  runtimeInputs = [
    git
  ];
  text = builtins.readFile ./better-branch.nu;
}
