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
  text = builtins.readFile ./toggle-theme.nu;
}
