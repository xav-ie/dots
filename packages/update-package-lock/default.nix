{
  writeNuApplication,
  git,
  nodejs,
}:
writeNuApplication {
  name = "update-package-lock";
  runtimeInputs = [
    git
    nodejs
  ];
  text = ./update-package-lock.nu |> builtins.readFile;
}
