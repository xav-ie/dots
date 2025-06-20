_: {
  config = {
    virtualisation = {
      podman = {
        enable = true;
        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;
        # Create a "docker" socket that just points to podman
        dockerSocket.enable = true;
        # # Required for containers under podman-compose to be able to talk to each other.
        # defaultNetwork.settings.dns_enabled = true;
      };
    };
    # generally good to have this set up
    systemd.tmpfiles.rules = [
      "d /media 0777 root root -"
    ];
  };
}
