{
  writeNuApplication,
}:
writeNuApplication {
  name = "at-computer";
  text = ./at-computer.nu |> builtins.readFile;
}
