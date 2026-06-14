{
  writeNuApplication,
}:
writeNuApplication {
  name = "format-staged";
  # just run with the current shell's `npx`
  text = ./format-staged.nu |> builtins.readFile;
}
