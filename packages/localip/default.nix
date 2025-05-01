{
  writeNuApplication,
}:
writeNuApplication {
  name = "localip";
  text = builtins.readFile ./localip.nu;
}
