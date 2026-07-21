{
  writeNuApplication,
  git,
  nodejs,
}:
writeNuApplication {
  name = "git-update-package-lock";
  runtimeInputs = [
    git
    nodejs
  ];
  text = ./git-update-package-lock.nu |> builtins.readFile;
}
