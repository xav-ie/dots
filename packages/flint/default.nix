{
  format-staged,
  lint-staged,
  writeNuApplication,
}:
writeNuApplication {
  name = "flint";
  runtimeInputs = [
    format-staged
    lint-staged
  ];
  # just run with the current shell's `npx`
  text = builtins.readFile ./flint.nu;
}
