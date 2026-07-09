{
  stdenv,
  swift,
}:
stdenv.mkDerivation {
  pname = "focus-daemon";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O *.swift -o focusd
    runHook postBuild
  '';
  # Ship as a .app bundle with a stable bundle id: the daemon needs Accessibility
  # for the AX window move, and the grant (tcc-grant, in _nox-body.nix activation)
  # pins this bundle's cdhash. Re-pins automatically when focusd's code changes.
  installPhase = ''
    runHook preInstall
    app=$out/Applications/focusd.app
    mkdir -p "$app/Contents/MacOS"
    cp focusd "$app/Contents/MacOS/focusd"
    cat > "$app/Contents/Info.plist" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>focusd</string>
      <key>CFBundleIdentifier</key><string>com.x.focusd</string>
      <key>CFBundleName</key><string>focusd</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1.0</string>
      <key>LSUIElement</key><true/>
    </dict></plist>
    EOF
    mkdir -p $out/bin
    ln -s "$app/Contents/MacOS/focusd" $out/bin/focusd
    runHook postInstall
  '';

  # Ad-hoc sign the bundle with its final identity (com.x.focusd) at BUILD time.
  # This must run in postFixup, not installPhase: stdenv's darwin fixup re-signs
  # Mach-Os it touches (Swift rpaths) and would revert the identifier back to
  # "focusd", breaking the pinned grant. Signing here bakes the exact cdhash the
  # Accessibility grant pins into the store bundle, so any later copy (activation
  # cp / spotlight ditto) preserves it — no install-time re-sign needed.
  # Uses Apple's /usr/bin/codesign for a full bundle seal (matches the cdhash the
  # grant already pins); needs __noChroot since the user has sandbox = "relaxed".
  __noChroot = true;
  postFixup = ''
    /usr/bin/codesign --force --sign - --identifier com.x.focusd \
      "$out/Applications/focusd.app"
  '';

  meta.mainProgram = "focusd";
}
