{
  coreutils,
  pinentry-gnome3,
  pinentry-tty,
  writeShellApplication,
}:
writeShellApplication {
  name = "pinentry";
  runtimeInputs = [
    coreutils
    pinentry-gnome3
    pinentry-tty
  ];
  text = ./pinentry-auto.sh |> builtins.readFile;
}
