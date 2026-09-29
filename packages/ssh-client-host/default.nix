{
  tailscale,
  writeNuApplication,
}:
writeNuApplication {
  name = "ssh-client-host";
  runtimeInputs = [ tailscale ];
  text = ./ssh-client-host.nu |> builtins.readFile;
}
