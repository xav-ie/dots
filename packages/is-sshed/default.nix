{
  writeNuApplication,
}:
writeNuApplication {
  name = "is-sshed";
  text = ./is-sshed.nu |> builtins.readFile;
}
