{
  writeNuApplication,
  notify,
  yabai,
}:
writeNuApplication {
  name = "focus-or-open-application";
  runtimeInputs = [
    notify
    yabai
  ];
  text = builtins.readFile ./focus-or-open-application.nu;
}
