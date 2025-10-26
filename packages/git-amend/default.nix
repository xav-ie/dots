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
  text = builtins.readFile ./git-amend.nu;
}
