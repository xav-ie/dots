{
  flake.modules.nixos.praesidium = {
    config = {
      # The RTL8125 negotiates Energy Efficient Ethernet with the switch and
      # then intermittently drops carrier for ~4s when entering low-power idle.
      # Matched by driver rather than interface name or MAC so it survives a
      # NIC rename and keeps hardware addresses out of the repo.
      systemd.network.links."10-no-eee-r8169" = {
        matchConfig.Driver = "r8169";
        extraConfig = ''
          [EnergyEfficientEthernet]
          Enable=false
        '';
      };
    };
  };
}
