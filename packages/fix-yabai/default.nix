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

  text = builtins.readFile ./fix-yabai.nu;
}
