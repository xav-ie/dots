{
  git,
  writeNuApplication,
  gnused,
}:
writeNuApplication {
  name = "git-amend";
  runtimeInputs = [
    git
    gnused
  ];
  text = ./git-amend.nu |> builtins.readFile;
}
