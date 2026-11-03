{
  writeNuApplication,
  yabai,
  jq,
  skhd,
}:
writeNuApplication {
  name = "fix-yabai";
  runtimeInputs = [
    yabai
    jq
    skhd
  ];

  text = ./fix-yabai.nu |> builtins.readFile;
}
