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
  text = ./notify.nu |> builtins.readFile;
}
