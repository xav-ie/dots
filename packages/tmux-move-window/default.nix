{
  writeNuApplication,
  tmux,
}:
writeNuApplication {
  name = "tmux-move-window";
  runtimeInputs = [
    tmux
  ];
  text = builtins.readFile ./tmux-move-window.nu;
}
