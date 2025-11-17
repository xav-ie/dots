{
  writeShellApplication,
  tmux,
  git,
}:
writeShellApplication {
  name = "tmux-tab-name-update";
  runtimeInputs = [
    tmux
    git
  ];
  text = builtins.readFile ./tmux-tab-name-update.bash;
}
