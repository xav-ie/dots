{
  flake.modules.nixos.praesidium = {
    services.local-networking.proxies.music-assistant = {
      subdomain = "music";
      port = 8095;
    };

    services.music-assistant = {
      enable = true;
      # Players pull audio from the stream port (8097), so it must be reachable on the LAN.
      openFirewall = true;
      providers = [
        "airplay"
        "chromecast"
        "hass"
        "hass_players"
        "radiobrowser"
        "ytmusic"
      ];
    };

    # YouTube streams need a proof of origin token; the ytmusic provider asks this
    # server at its default 127.0.0.1:4416. Unauthenticated, so loopback only.
    # The image tracks the bgutil-ytdlp-pot-provider plugin version in nixpkgs.
    virtualisation.oci-containers.containers.bgutil-pot-provider = {
      image = "docker.io/brainicism/bgutil-ytdlp-pot-provider:2.0.0";
      ports = [ "127.0.0.1:4416:4416" ];
      extraOptions = [ "--init" ];
    };
  };
}
