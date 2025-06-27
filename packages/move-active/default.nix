{
  writeNuApplication,
  nushell,
  hyprland,
  jq,
}:
writeNuApplication {
  name = "move-active";
  runtimeInputs = [
    nushell
    hyprland
    jq
  ];
  text = builtins.readFile ./move-active.nu;
}
