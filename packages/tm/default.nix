{
  writeShellApplication,
  tmux,
}:
writeShellApplication {
  name = "tm";
  runtimeInputs = [ tmux ];
  text = ''
    tmux attach || exec tmux
  '';
}
