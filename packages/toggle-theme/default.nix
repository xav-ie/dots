{
  writeNuApplication,
  dconf,
}:
writeNuApplication {
  name = "toggle-theme";
  runtimeInputs = [
    dconf
  ];
  text = ./toggle-theme.nu |> builtins.readFile;
}
