{
  coreutils,
  pinentry-curses,
  pinentry-gnome3,
  writeShellApplication,
}:
writeShellApplication {
  name = "pinentry";
  runtimeInputs = [
    coreutils
    pinentry-curses
    pinentry-gnome3
  ];
  text = ./pinentry-auto.sh |> builtins.readFile;
}
