{
  writeNuApplication,
  generate-kaomoji,
  libnotify,
  openssh,
  ssh-client-host,
}:
writeNuApplication {
  name = "notify";
  runtimeInputs = [
    generate-kaomoji
    libnotify
    openssh
    ssh-client-host
  ];
  text = ./notify.nu |> builtins.readFile;
}
