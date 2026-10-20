{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    {
      services.local-networking.proxies.music-assistant = {
        subdomain = "music";
        port = 8095;
      };

      services.music-assistant = {
        enable = true;
        # 2.10.6 holds an AirPlay 2 speaker for 120 s after a stream ends, so an
        # announcement in that window waits 7 s on a dead session. Fixed in 2.10.7.
        # makeOverridable keeps .override, which the module uses to add the providers.
        package = pkgs.lib.makeOverridable (
          args:
          (pkgs.music-assistant.override args).overridePythonAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              (pkgs.fetchpatch {
                url = "https://github.com/music-assistant/server/commit/79072313087146021687617de3d2f1949493e64e.patch";
                hash = "sha256-HD2kVD837gM+PZ1gz6Czc18+yxfC6XBtJQSvLdFFGis=";
              })
            ];
          })
        ) { };
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
