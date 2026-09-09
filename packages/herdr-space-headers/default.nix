{
  writeNuApplication,
}:
writeNuApplication {
  name = "herdr-space-headers";
  text = ./herdr-space-headers.nu |> builtins.readFile;
}
