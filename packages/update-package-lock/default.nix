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
  text = builtins.readFile ./update-package-lock.nu;
}
