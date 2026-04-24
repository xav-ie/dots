{
  writeNuApplication,
}:
writeNuApplication {
  name = "tsc-filter";
  text = builtins.readFile ./tsc-filter.nu;
}
