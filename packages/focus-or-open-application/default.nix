{
  writeNuApplication,
  yabai,
}:
writeNuApplication {
  name = "focus-or-open-application";
  runtimeInputs = [
    yabai
  ];
  text = ./focus-or-open-application.nu |> builtins.readFile;
}
