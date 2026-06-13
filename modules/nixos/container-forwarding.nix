{
  # Podman's bridge networks (mcp-proxy, postiz, …) NAT container traffic out
  # through the host's uplink, which the kernel only routes with IPv4 forwarding
  # on. NixOS defaults `net.ipv4.conf.all.forwarding` to 0; setting the same key
  # (rather than its `net.ipv4.ip_forward` alias, which loses the conflict)
  # turns container egress on and keeps it across switches.
  flake.modules.nixos.praesidium.boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;
}
