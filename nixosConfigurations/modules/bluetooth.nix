{ config, lib, ... }:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  bluemanAppletEnabled = hmConfig.services.blueman-applet.enable or false;
in
{
  config = lib.mkMerge [
    # Always enable bluetooth hardware support
    {
      hardware.bluetooth.enable = true;
    }

    # Conditionally enable blueman service when blueman-applet is used
    (lib.mkIf bluemanAppletEnabled {
      services.blueman.enable = true;
    })
  ];
}
