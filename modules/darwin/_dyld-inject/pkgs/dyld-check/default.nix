{
  writeNuApplication,
}:
writeNuApplication {
  name = "dyld-check";
  runtimeInputs = [ ];

  text = builtins.readFile ./dyld-check.nu;
}
