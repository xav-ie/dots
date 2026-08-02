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
      };
      # podman.service defaults to LOGGING="--log-level=info", which logs one
      # line per REST call. Traefik's docker provider watches the event stream
      # and re-inspects every container on each event, and the postgres/redis
      # healthchecks emit events constantly — ~200 lines/min, 80k per boot, and
      # 90% of the journal. Traefik v3 has no poll interval to turn down (the
      # docker provider is event-driven), so quiet the logging instead.
      systemd.services.podman.environment.LOGGING = "--log-level=warn";

      # generally good to have this set up
      systemd.tmpfiles.rules = [
        "d /media 0755 root root -"
      ];
    };
  };
}
