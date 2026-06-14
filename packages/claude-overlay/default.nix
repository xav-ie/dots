{
  writeShellApplication,
  util-linux,
  rsync,
  findutils,
}:
writeShellApplication {
  name = "claude-overlay";
  runtimeInputs = [
    util-linux # unshare
    rsync # apply step
    findutils # find for diff review
  ];
  text = ./claude-overlay.sh |> builtins.readFile;
}
