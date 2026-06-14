{
  car-edit,
  writeNuApplication,
}:
writeNuApplication {
  name = "aqua-patcher";
  runtimeInputs = [ car-edit ];

  text = ./aqua-patcher.nu |> builtins.readFile;
}
