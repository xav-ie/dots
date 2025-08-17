{
  writeNuApplication,
}:
writeNuApplication {
  name = "is-sshed";
  text = builtins.readFile ./is-sshed.nu;
}
