{
  writeNuApplication,
  tmux,
  git,
}:
writeNuApplication {
  name = "tmux-tab-name-update";
  runtimeInputs = [
    tmux
    git
  ];
  text = builtins.readFile ./tmux-tab-name-update.nu;
}
