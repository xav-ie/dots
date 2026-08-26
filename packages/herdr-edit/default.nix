{
  writeNuApplication,
}:
writeNuApplication {
  name = "herdr-edit";
  text = ./herdr-edit.nu |> builtins.readFile;
}
