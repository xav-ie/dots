{
  writeNuApplication,
  zenity,
  systemd,
}:
writeNuApplication {
  name = "zenity-askpass";
  runtimeInputs = [
    zenity
    systemd
  ];
  text = builtins.readFile ./zenity-askpass.nu;
}
