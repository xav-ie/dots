# Tetherbug (github.com/xav-ie/Tetherbug): asks the Android phone over Bluetooth LE to
# turn its hotspot on when the Mac's Wi-Fi is disconnected, and makes macOS treat it as
# a Personal Hotspot.
{
  flake.modules.darwin.macos =
    { inputs, pkgs, ... }:
    let
      # macOS never shows the windowless agent the Bluetooth prompt, and nox's apps can't
      # prompt at all (AMFI off makes them platform binaries). The private entitlement grants
      # Bluetooth instead; honored only because nox boots amfi_get_out_of_my_way=1.
      entitlements =
        pkgs.writeText "tetherbug.entitlements" # xml
          ''
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>com.apple.private.tcc.allow</key>
              <array><string>kTCCServiceBluetoothAlways</string></array>
            </dict></plist>
          '';
    in
    {
      imports = [ inputs.tetherbug.darwinModules.default ];

      services.tetherbug = {
        enable = true;
        package =
          inputs.tetherbug.packages.${pkgs.stdenv.hostPlatform.system}.tetherbug.overrideAttrs
            (old: {
              postFixup = old.postFixup + ''
                codesign --force --sign - --identifier ie.xav.tetherbug --entitlements ${entitlements} \
                  "$out/Applications/Tetherbug.app/Contents/MacOS/Tetherbug"
              '';
            });
      };
    };
}
