{
  writeNuApplication,
  sqlite,
}:
writeNuApplication {
  name = "tcc-grant";
  runtimeInputs = [
    sqlite
  ];
  text = builtins.readFile ./tcc-grant.nu;
}
