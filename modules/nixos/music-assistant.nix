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
  };
}
