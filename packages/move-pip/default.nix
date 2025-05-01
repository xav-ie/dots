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
  text = builtins.readFile ./move-pip.nu;
}
