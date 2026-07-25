{
  stdenv,
  swift,
}:
# hidewin-bar — menubar manager for the hide-windows agent. Lists running
# apps and toggles each between hidden/visible to screen capture by
# posting distributed notifications the injected agent observes. Needs no
# TCC/entitlements (NSWorkspace + distributed notifications only), so it's
# a plain ad-hoc .app run as a launchd agent (see modules/darwin/
# hidewin-bar.nix). LSUIElement so it's menubar-only, no Dock icon.
stdenv.mkDerivation {
  pname = "hidewin-bar";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O *.swift -o hidewin-bar
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    app=$out/Applications/hidewin-bar.app
    mkdir -p "$app/Contents/MacOS"
    cp hidewin-bar "$app/Contents/MacOS/hidewin-bar"
    cat > "$app/Contents/Info.plist" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>hidewin-bar</string>
      <key>CFBundleIdentifier</key><string>com.x.hidewin-bar</string>
      <key>CFBundleName</key><string>hidewin-bar</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1.0</string>
      <key>LSUIElement</key><true/>
    </dict></plist>
    EOF
    mkdir -p $out/bin
    ln -s "$app/Contents/MacOS/hidewin-bar" $out/bin/hidewin-bar
    runHook postInstall
  '';
  meta.mainProgram = "hidewin-bar";
}
