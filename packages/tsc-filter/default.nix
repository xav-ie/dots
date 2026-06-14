{
  writeNuApplication,
}:
writeNuApplication {
  name = "tsc-filter";
  text = ./tsc-filter.nu |> builtins.readFile;
}
