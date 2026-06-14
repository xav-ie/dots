{
  writeNuApplication,
  dconf,
  tmux,
}:
writeNuApplication {
  name = "toggle-theme";
  runtimeInputs = [
    tmux
    dconf
  ];
  text = ./toggle-theme.nu |> builtins.readFile;
}
