{
  writeNuApplication,
}:
writeNuApplication {
  name = "localip";
  text = ./localip.nu |> builtins.readFile;
}
