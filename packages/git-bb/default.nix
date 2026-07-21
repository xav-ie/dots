{
  writeNuApplication,
  git,
}:
writeNuApplication {
  name = "git-bb";
  runtimeInputs = [
    git
  ];
  text = ./git-bb.nu |> builtins.readFile;
}
