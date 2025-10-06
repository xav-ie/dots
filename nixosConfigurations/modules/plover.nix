{ config, lib, ... }:
{
  options = {
    services.plover = {
      enable = lib.mkEnableOption "Plover stenography support";
    };
  };

  config = lib.mkIf config.services.plover.enable {
    # Add udev rule to allow input group to access /dev/uinput for character output
    services.udev.extraRules = ''
      KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    '';

    # Add input group for /dev/uinput access and dialout group for serial port access
    users.users."${config.defaultUser}".extraGroups = [
      "input"
      "dialout"
    ];
  };
}
