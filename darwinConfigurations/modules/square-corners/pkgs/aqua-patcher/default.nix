{
  car-edit,
  writeNuApplication,
}:
writeNuApplication {
  name = "aqua-patcher";
  runtimeInputs = [ car-edit ];

  text = builtins.readFile ./aqua-patcher.nu;
}
