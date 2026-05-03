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
  text = builtins.readFile ./pinentry-auto.sh;
}
