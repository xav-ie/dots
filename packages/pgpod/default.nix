{
  writeNuApplication,
  pstree,
}:
writeNuApplication {
  name = "pgpod";
  runtimeInputs = [
    pstree
  ];
  text = builtins.readFile ./pgpod.nu;
}
