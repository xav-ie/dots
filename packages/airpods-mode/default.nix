{
  stdenv,
  swift,
}:
# Sets the AirPods listening mode (ANC/Transparency/Off/Adaptive) directly over
# Bluetooth by speaking Apple's Accessory Protocol on the L2CAP AAP channel
# (PSM 0x1001), no Control Center UI scripting. IOBluetooth + CoreBluetooth
# auto-link on `import` under swiftc on darwin (same as focus-daemon).
#
# Shipped as a .app bundle with a stable bundle id: IOBluetooth's pairedDevices()
# and the L2CAP open are gated by the Bluetooth TCC permission, and the grant
# (tcc-grant, in _nox-body.nix activation) pins this bundle's cdhash. Re-pins
# automatically when the code changes. NSBluetoothAlwaysUsageDescription is
# required for the permission to be grantable at all.
stdenv.mkDerivation {
  pname = "airpods-mode";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O *.swift -o airpods-mode
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    app=$out/Applications/airpods-mode.app
    mkdir -p "$app/Contents/MacOS"
    cp airpods-mode "$app/Contents/MacOS/airpods-mode"
    # CFBundleIdentifier MUST start with com.apple. — mediaremoted gates
    # now-playing access by bundle-id prefix, so the --daemon play/pause reads
    # only work (don't wedge) with a com.apple.* id. The re-sign in _nox-body.nix
    # activation uses --identifier com.apple.airpods-mode to match.
    cat > "$app/Contents/Info.plist" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>airpods-mode</string>
      <key>CFBundleIdentifier</key><string>com.apple.airpods-mode</string>
      <key>CFBundleName</key><string>airpods-mode</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1.0</string>
      <key>LSUIElement</key><true/>
      <key>NSBluetoothAlwaysUsageDescription</key><string>Set AirPods listening mode over the AAP channel.</string>
    </dict></plist>
    EOF
    # Ship the entitlements so the activation re-sign can reference them.
    cp ${./airpods-mode.entitlements} $out/airpods-mode.entitlements
    mkdir -p $out/bin
    ln -s "$app/Contents/MacOS/airpods-mode" $out/bin/airpods-mode
    runHook postInstall
  '';
  meta.mainProgram = "airpods-mode";
}
