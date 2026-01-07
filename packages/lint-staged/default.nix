{
  writeNuApplication,
}:
writeNuApplication {
  name = "lint-staged";
  # just run with the current shell's `npx`
  text = builtins.readFile ./lint-staged.nu;
}
