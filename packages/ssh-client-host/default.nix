{
  writeNuApplication,
}:
writeNuApplication {
  name = "ssh-client-host";
  text = ./ssh-client-host.nu |> builtins.readFile;
}
