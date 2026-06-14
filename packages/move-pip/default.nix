{
  writeNuApplication,
  fzf,
  jq,
  yabai,
}:
writeNuApplication {
  name = "move-pip";
  runtimeInputs = [
    fzf
    jq
    yabai
  ];
  text = ./move-pip.nu |> builtins.readFile;
}
