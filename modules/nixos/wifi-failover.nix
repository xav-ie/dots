{
  flake.modules.nixos.praesidium =
    { config, pkgs, ... }:
    {
      config = {
        # Wi-Fi is a fallback, not a peer. While any ethernet device is
        # connected the radio stays off, so praesidium holds exactly one
        # default route and one source address; unplugging brings it back.
        #
        # The radio is only half of it. Turning it on does not mean a link
        # came up: if NetworkManager decides the stored secret is stale it
        # asks a secret agent instead, nm-applet raises a dialog, and the
        # dialog waits forever. Remote, that is a lockout. So the PSK is
        # declared from sops (system-owned, never agent-owned) and a timer
        # re-checks that the fallback actually carried.

        sops = {
          secrets = {
            "wifi/home/psk" = { };
            "wifi/home/ssid" = { };
          };
          # Single quotes keep systemd's EnvironmentFile parser from touching
          # spaces or backslashes in the values.
          templates."wifi.env".content = ''
            WIFI_HOME_PSK='${config.sops.placeholder."wifi/home/psk"}'
            WIFI_HOME_SSID='${config.sops.placeholder."wifi/home/ssid"}'
          '';
        };

        networking.networkmanager.ensureProfiles = {
          environmentFiles = [ config.sops.templates."wifi.env".path ];

          # Add a block per network. envsubst runs over every field, so the
          # SSID stays out of the repo along with the PSK.
          profiles.home = {
            connection = {
              id = "$WIFI_HOME_SSID";
              type = "wifi";
              autoconnect = true;
              autoconnect-priority = 100;
            };
            wifi = {
              ssid = "$WIFI_HOME_SSID";
              mode = "infrastructure";
            };
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = "$WIFI_HOME_PSK";
            };
            ipv4.method = "auto";
            ipv6.method = "auto";
          };
        };

        networking.networkmanager.dispatcherScripts = [
          {
            type = "basic";
            source =
              pkgs.writeShellScript "wifi-failover" # sh
                ''
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

        # The dispatcher reacts; this heals. It re-asserts the same invariant
        # on a schedule, so a failed association, a missed dispatcher event, or
        # a resume-from-sleep recovers on its own instead of waiting for a
        # human to click a dialog that nobody is sitting in front of.
        systemd.services.wifi-failover-heal = {
          description = "Ensure praesidium has an uplink when ethernet is down";
          after = [ "NetworkManager.service" ];
          wants = [ "NetworkManager.service" ];
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.gawk
            pkgs.networkmanager
          ];
          script = # sh
            ''
              set -u

              if nmcli -t -f TYPE,STATE device | grep -q '^ethernet:connected$'; then
                nmcli radio wifi off || true
                exit 0
              fi

              nmcli radio wifi on || true

              if nmcli -t -f TYPE,STATE device | grep -q '^wifi:connected$'; then
                exit 0
              fi

              # Autoconnect has had its chance by now. Walk the saved wifi
              # profiles by descending priority and ask for each explicitly.
              old_ifs=$IFS
              IFS='
              '
              set -- $(nmcli -t -f NAME,TYPE,AUTOCONNECT-PRIORITY connection show \
                | awk -F: '$2 == "802-11-wireless" { printf "%s:%s\n", $3, $1 }' \
                | sort -t: -k1,1nr \
                | cut -d: -f2-)
              IFS=$old_ifs

              for name in "$@"; do
                echo "wifi-failover: trying $name"
                if nmcli --wait 20 connection up "$name" >/dev/null 2>&1; then
                  echo "wifi-failover: up on $name"
                  exit 0
                fi
              done

              echo "wifi-failover: no saved network would associate" >&2
              exit 1
            '';
        };

        systemd.timers.wifi-failover-heal = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitInactiveSec = "5min";
            # How late systemd may fire, so it can batch wakeups. Worst case
            # offline window is this plus the interval, which is the number
            # that matters when the box is remote and the link is down.
            AccuracySec = "30s";
          };
        };
      };
    };
}
