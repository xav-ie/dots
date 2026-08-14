{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    {
      config = {
        # Wi-Fi is a fallback, not a peer. While any ethernet device is
        # connected the radio stays off, so praesidium holds exactly one
        # default route and one source address; unplugging brings it back.
        networking.networkmanager.dispatcherScripts = [
          {
            type = "basic";
            source = pkgs.writeShellScript "wifi-failover" ''
              iface="$1"
              action="$2"

              case "$action" in
                up | down) ;;
                *) exit 0 ;;
              esac

              nmcli=${pkgs.networkmanager}/bin/nmcli

              # Toggling the radio emits events for the Wi-Fi device itself;
              # acting on those would loop.
              devtype=$("$nmcli" -t -f DEVICE,TYPE device | ${pkgs.gnugrep}/bin/grep "^$iface:" | ${pkgs.coreutils}/bin/cut -d: -f2)
              case "$devtype" in
                wifi | wifi-p2p | "") exit 0 ;;
              esac

              if "$nmcli" -t -f TYPE,STATE device | ${pkgs.gnugrep}/bin/grep -q '^ethernet:connected$'; then
                "$nmcli" radio wifi off
              else
                "$nmcli" radio wifi on
              fi
            '';
          }
        ];
      };
    };
}
