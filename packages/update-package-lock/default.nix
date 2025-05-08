{
  writeNuApplication,
  git,
  nodejs,
}:
writeNuApplication {
  name = "update-pacakge-lock";
  runtimeInputs = [
    git
    nodejs
  ];
  text = builtins.readFile ./update-package-lock.nu;
}
