{
  writeNuApplication,
  yabai,
}:
writeNuApplication {
  name = "focus-or-open-application";
  runtimeInputs = [
    yabai
  ];
  text = builtins.readFile ./focus-or-open-application.nu;
}
