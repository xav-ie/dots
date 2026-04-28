{
  config,
  lib,
  pkgs,
  ...
}:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  bluemanAppletEnabled = hmConfig.services.blueman-applet.enable or false;

  bluetooth-auto-block = pkgs.writeNuApplication {
    name = "bluetooth-auto-block";
    runtimeInputs = with pkgs; [
      util-linux
      bluez
      coreutils
    ];
    text = # nu
      ''
        const STATE_FILE = "/var/lib/bluetooth-auto-block/last-connected"
        const IDLE_TIMEOUT = 3600  # 1 hour in seconds

        # Check if bluetooth is blocked
        let blocked = (rfkill list bluetooth | lines | find "Soft blocked" | str trim | split column ": " | get column2.0 | ansi strip)

        if $blocked == "yes" {
          # Bluetooth is blocked, clean up state file if it exists
          if ($STATE_FILE | path exists) {
            rm -f $STATE_FILE
          }
          exit 0
        }

        # Check for connected devices
        let connected = (bluetoothctl devices Connected | lines | parse "Device {mac} {name}" | length)

        if $connected > 0 {
          # Devices are connected, update timestamp
          mkdir ($STATE_FILE | path dirname)
          date now | format date "%s" | save -f $STATE_FILE
          exit 0
        }

        # No devices connected - check how long it's been idle
        if not ($STATE_FILE | path exists) {
          # First time seeing no connections, create state file
          mkdir ($STATE_FILE | path dirname)
          date now | format date "%s" | save -f $STATE_FILE
          exit 0
        }

        # Read last connected timestamp
        let last_connected = (open $STATE_FILE | into int)
        let current_time = (date now | format date "%s" | into int)
        let idle_duration = ($current_time - $last_connected)

        if $idle_duration > $IDLE_TIMEOUT {
          # Been idle for over an hour, block bluetooth
          rfkill block bluetooth
          rm -f $STATE_FILE
        }
      '';
  };
in
{
  config = lib.mkMerge [
    # Always enable bluetooth hardware support
    {
      hardware.bluetooth = {
        enable = true;
        # BAP (LE Audio) needs ISO sockets behind KernelExperimental;
        # we have no LE Audio devices that work cleanly over Linux/BlueZ
        # so skip the plugin to avoid the "BAP requires ISO Socket"
        # warning. NixOS turns this into `--noplugin=bap` on bluetoothd.
        disabledPlugins = [ "bap" ];
        settings = {
          General = {
            # Short discoverable window (seconds) — limits how long this
            # adapter is visible to other devices when discoverable is toggled on.
            # 0 means "forever", so use a sane default.
            DiscoverableTimeout = 30;
            # Required for Home Assistant passive BLE scanning
            Experimental = true;
          };
        };
      };

      # systemd-rfkill restores the persistent rfkill state from the previous
      # session at boot, which means BT comes up soft-blocked from the
      # rfkill-bluetooth.timer's previous run. bluetoothd then races against
      # rfkill during init and logs "Failed to set mode (0x03)", and HA's BT
      # MGMT probe gets "Not Powered" → misleading NET_ADMIN warning.
      # Force-unblock before bluetoothd touches the adapter, so it inits
      # cleanly. The rfkill-bluetooth.timer below re-blocks 10min later.
      systemd.services.bluetooth.serviceConfig.ExecStartPre = [
        "${lib.getExe' pkgs.util-linux "rfkill"} unblock bluetooth"
      ];

      # Block bluetooth by default to prevent discovery/CPU drain.
      # Delayed 10min after boot so home-assistant has time to do its initial
      # BT MGMT probe before the adapter goes "Not Powered" — habluetooth
      # otherwise logs a misleading "missing NET_ADMIN/NET_RAW" error every boot.
      # Use Waybar bluetooth toggle to enable manually after this.
      systemd.services.rfkill-bluetooth = {
        description = "Block Bluetooth";
        after = [ "bluetooth.service" ];
        path = [ pkgs.util-linux ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe' pkgs.util-linux "rfkill"} block bluetooth";
          RemainAfterExit = true;
        };
      };

      systemd.timers.rfkill-bluetooth = {
        description = "Block Bluetooth 10min after boot";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          Unit = "rfkill-bluetooth.service";
        };
      };

      # Auto-block bluetooth after 1 hour of no connections
      systemd.services.bluetooth-auto-block = {
        description = "Auto-block bluetooth when idle for >1 hour";
        after = [ "bluetooth.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${bluetooth-auto-block}/bin/bluetooth-auto-block";
          StateDirectory = "bluetooth-auto-block";
        };
      };

      systemd.timers.bluetooth-auto-block = {
        description = "Timer for bluetooth auto-block";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "15min";
          OnUnitActiveSec = "15min";
          Unit = "bluetooth-auto-block.service";
        };
      };
    }

    # Conditionally enable blueman service when blueman-applet is used
    (lib.mkIf bluemanAppletEnabled {
      services.blueman.enable = true;
    })
  ];
}
