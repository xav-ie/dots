# hotspot-wake: when Wi-Fi stays without an address, poke the Android phone over
# Bluetooth. An Essentials automation on the phone (Bluetooth connected → Turn On
# Hotspot) turns its hotspot on, and macOS auto-joins it as a known network. Pokes
# back off 2s → 30s; each is a brief connect/disconnect so the phone sees a fresh event.
_: {
  flake.modules.darwin.macos =
    { config, pkgs, ... }:
    let
      # Under launchd, Bluetooth TCC denies blueutil (power reads 0, no paired
      # devices). The private entitlement grants it; honored only because nox
      # boots amfi_get_out_of_my_way=1.
      blueutil =
        pkgs.runCommand "blueutil-entitled"
          {
            nativeBuildInputs = [
              pkgs.cctools
              pkgs.darwin.sigtool
            ];
          } # sh
          ''
            mkdir -p $out/bin
            cp ${pkgs.blueutil}/bin/blueutil $out/bin/
            chmod u+w $out/bin/blueutil
            codesign -f -s - --entitlements ${entitlements} $out/bin/blueutil
          '';
      entitlements =
        pkgs.writeText "blueutil.entitlements" # xml
          ''
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>com.apple.private.tcc.allow</key>
              <array><string>kTCCServiceBluetoothAlways</string></array>
            </dict></plist>
          '';
      hotspot-wake = pkgs.writeShellApplication {
        name = "hotspot-wake";
        runtimeInputs = [ blueutil ];
        text = # sh
          ''
            phone=$(cat ${config.sops.secrets."hotspot-wake/phone_bt_address".path})
            offline_since=0
            while sleep 2; do
              now=$(date +%s)
              if /usr/sbin/ipconfig getifaddr en0 >/dev/null ||
                [ "$(/usr/sbin/networksetup -getairportpower en0 | awk '{print $NF}')" != On ] ||
                [ "$(blueutil --power)" != 1 ]; then
                offline_since=0
                continue
              fi
              if [ "$offline_since" = 0 ]; then
                # Give macOS's own auto-join (which bursts on wake) a head start.
                offline_since=$now
                next_poke=$((now + 5))
                backoff=2
                /usr/bin/osascript -e 'display notification "Asking phone to turn on its hotspot…" with title "No Wi-Fi"'
              fi
              [ "$now" -lt "$next_poke" ] && continue
              echo "$(date) no Wi-Fi, poking phone"
              # Disconnect again so every poke is a fresh "connected" event for the phone.
              if blueutil --connect "$phone"; then
                sleep 2
                blueutil --disconnect "$phone" || true
              fi
              next_poke=$(($(date +%s) + backoff))
              backoff=$((backoff * 2 > 30 ? 30 : backoff * 2))
            done
          '';
      };
    in
    {
      sops.secrets."hotspot-wake/phone_bt_address" = {
        owner = config.defaultUser;
        mode = "0400";
      };

      launchd.user.agents.hotspot-wake.serviceConfig = {
        ProgramArguments = [ "${hotspot-wake}/bin/hotspot-wake" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/hotspot-wake.out.log";
        StandardErrorPath = "/tmp/hotspot-wake.err.log";
      };
    };
}
