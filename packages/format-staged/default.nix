{
  writeNuApplication,
}:
writeNuApplication {
  name = "format-staged";
  # just run with the current shell's `npx`
  text = builtins.readFile ./format-staged.nu;
}
