{
  writeNuApplication,
  sqlite,
}:
writeNuApplication {
  name = "tcc-grant";
  runtimeInputs = [
    sqlite
  ];
  text = ./tcc-grant.nu |> builtins.readFile;
}
