{
  writeNuApplication,
  pstree,
}:
writeNuApplication {
  name = "pgpod";
  runtimeInputs = [
    pstree
  ];
  text = ./pgpod.nu |> builtins.readFile;
}
