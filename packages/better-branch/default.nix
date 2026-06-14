{
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "better-branch";
  runtimeInputs = [
    git
  ];
  text = ./better-branch.nu |> builtins.readFile;
}
