{
  librsvg,
  stdenv,
  swift,
}:
# Notifier.app: posts `notify` notifications on macOS with a per-notification
# avatar and a click command, and runs as a launchd agent to handle clicks,
# expire old notifications and report wake/unlock. See main.swift.
stdenv.mkDerivation {
  pname = "notifier";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [
    librsvg
    swift
  ];
  buildPhase = ''
    runHook preBuild
    swiftc -O main.swift -o notifier
    mkdir icon.iconset
    for size in 16 32 128 256 512; do
      rsvg-convert -w $size -h $size icon.svg -o icon.iconset/icon_''${size}x''${size}.png
      rsvg-convert -w $((size * 2)) -h $((size * 2)) icon.svg -o icon.iconset/icon_''${size}x''${size}@2x.png
    done
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    app="$out/Applications/Notifier.app"
    mkdir -p "$app/Contents/MacOS" "$out/bin"
    cp Info.plist "$app/Contents/Info.plist"
    cp notifier "$app/Contents/MacOS/notifier"
    mkdir -p "$app/Contents/Resources"
    /usr/bin/iconutil -c icns icon.iconset -o "$app/Contents/Resources/icon.icns"
    ln -s "$app/Contents/MacOS/notifier" "$out/bin/notifier"
    runHook postInstall
  '';

  # Sign after stdenv's darwin fixup, which re-signs the Mach-O it touches and
  # would drop the entitlement. The communication-notification entitlement is
  # restricted; it loads only because this machine runs with AMFI relaxed.
  __noChroot = true;
  postFixup = ''
    /usr/bin/codesign --force --sign - --identifier com.x.notifier \
      --entitlements ${./entitlements.plist} "$out/Applications/Notifier.app"
  '';

  meta.mainProgram = "notifier";
}
