{
  writeNuApplication,
  tmux,
}:
writeNuApplication {
  name = "tmux-move-window";
  runtimeInputs = [
    tmux
  ];
  text = ./tmux-move-window.nu |> builtins.readFile;
}
