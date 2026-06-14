{
  writeNuApplication,
}:
writeNuApplication {
  name = "dyld-check";
  runtimeInputs = [ ];

  text = ./dyld-check.nu |> builtins.readFile;
}
