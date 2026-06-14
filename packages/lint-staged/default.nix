{
  writeNuApplication,
}:
writeNuApplication {
  name = "lint-staged";
  # just run with the current shell's `npx`
  text = ./lint-staged.nu |> builtins.readFile;
}
