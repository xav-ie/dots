{
  writeNuApplication,
  yabai,
  jq,
}:
writeNuApplication {
  name = "fix-yabai";
  runtimeInputs = [
    yabai
    jq
  ];

  text = ./fix-yabai.nu |> builtins.readFile;
}
