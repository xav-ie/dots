{
  writeNuApplication,
  libnotify,
  generate-kaomoji,
}:
writeNuApplication {
  name = "notify";
  runtimeInputs = [
    libnotify
    generate-kaomoji
  ];
  text = builtins.readFile ./notify.nu;
}
