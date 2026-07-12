{
  writeNuApplication,
  cloudflared,
  coreutils,
  curl,
  netcat,
  tailscale,
}:
writeNuApplication {
  name = "ssh-praesidium-route";
  runtimeInputs = [
    cloudflared
    coreutils
    curl
    netcat
    tailscale
  ];
  text = builtins.readFile ./ssh-praesidium-route.nu;
}
