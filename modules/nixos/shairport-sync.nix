{
  # AirPlay receiver "Desk" on the desktop speakers, playing into the user's
  # PipeWire session. Classic AirPlay (RAOP, NTP timing): AirPlay 2 needs nqptp,
  # which requires exclusive use of UDP 319/320, and Music Assistant's PTP clock
  # daemon already holds them on this host. Music Assistant still syncs it with
  # AirPlay 2 speakers, anchoring every group member to the same start instant.
  flake.modules.nixos.praesidium =
    { config, pkgs, ... }:
    let
      configFile = (pkgs.formats.libconfig { }).generate "shairport-sync.conf" {
        general = {
          mdns_backend = "avahi";
          name = "Desk";
          output_backend = "pipewire";
        };
      };
    in
    {
      # shairport-sync advertises through Avahi; Home Assistant and Music Assistant
      # keep their own mDNS responders alongside it.
      services.avahi = {
        enable = true;
        publish = {
          enable = true;
          userServices = true;
        };
      };

      # RTSP on TCP 5000, audio, control and timing on UDP 6001-6011.
      networking.firewall = {
        allowedTCPPorts = [ 5000 ];
        allowedUDPPortRanges = [
          {
            from = 6001;
            to = 6011;
          }
        ];
      };

      systemd.user.services.shairport-sync = {
        description = "AirPlay receiver";
        wantedBy = [ "default.target" ];
        after = [ "pipewire.service" ];
        wants = [ "pipewire.service" ];
        partOf = [ "pipewire.service" ];
        unitConfig.ConditionUser = config.defaultUser;
        serviceConfig = {
          ExecStart = "${pkgs.shairport-sync}/bin/shairport-sync -c ${configFile}";
          Restart = "on-failure";
        };
      };
    };
}
