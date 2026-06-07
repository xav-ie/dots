{
  flake.modules.nixos.linux = {
    # Force upower to start at boot (NixOS only socket-activates it via
    # DBus by default). PipeWire's bluez5 plugin queries upower during
    # wireplumber init for headphone battery levels, before DBus
    # activation can complete on a cold boot — first query gets
    # "Failed to get percentage from UPower: NameHasNoOwner".
    services.upower.enable = true;
    systemd.services.upower.wantedBy = [ "multi-user.target" ];
  };
}
