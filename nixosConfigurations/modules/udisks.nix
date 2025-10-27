{ config, lib, ... }:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  udiskieEnabled = hmConfig.services.udiskie.enable or false;
in
{
  config = lib.mkIf udiskieEnabled {
    # Enable udisks2 for automatic disk mounting when udiskie is used
    services.udisks2.enable = true;
  };
}
