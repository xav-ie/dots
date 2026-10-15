{
  flake.modules.nixos.linux = _: {
    config = {
      virtualisation = {
        podman = {
          enable = true;
          autoPrune = {
            enable = true;
            dates = "weekly";
          };
          # Create a `docker` alias for podman, to use it as a drop-in replacement
          dockerCompat = true;
          # Create a "docker" socket that just points to podman
          dockerSocket.enable = true;
          # # Required for containers under podman-compose to be able to talk to each other.
          # defaultNetwork.settings.dns_enabled = true;
        };
        # The journald events backend writes events it can't read back (even
        # `podman events` sees nothing), so traefik's docker provider never
        # hears a container restart and keeps routing to its old IP (502s).
        containers.containersConf.settings.engine.events_logger = "file";
      };
      # The default --log-level=info logs one line per REST call, and traefik's
      # event-driven docker provider re-inspects on every healthcheck event —
      # 80k lines per boot. Traefik v3 has no poll interval to turn down.
      systemd.services.podman.environment.LOGGING = "--log-level=warn";

      # generally good to have this set up
      systemd.tmpfiles.rules = [
        "d /media 0755 root root -"
      ];
    };
  };
}
