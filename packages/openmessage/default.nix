# OpenMessage, cut over to rcsd: a private fork of MaxGhenis/openmessage
# stripped to Google Messages (SMS/RCS) only. Every fix that used to live in
# a patch pile is committed in the fork (branch main). The fork also carries
# the native macOS app (mirrors macos/build.sh: Go backend in
# Contents/Resources, Swift app in Contents/MacOS, ad-hoc signed). Source and
# backend both come from the rcsd package (the `rcsd-src` flake input).
{
  lib,
  rcsd,
  stdenv,
  swift,
  swiftpm,
}:
stdenv.mkDerivation {
  pname = "openmessage";
  inherit (rcsd) version src;

  # The flake input is a /nix/store/<hash>-source path, unpacked to ./source.
  sourceRoot = "source/macos/OpenMessage";

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  buildPhase = ''
    runHook preBuild
    swift build -c release --disable-sandbox
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app=$out/Applications/OpenMessage.app
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" $out/bin
    cp "$(swift build -c release --show-bin-path)/OpenMessage" "$app/Contents/MacOS/OpenMessage"
    cp ${lib.getExe rcsd} "$app/Contents/Resources/openmessage"
    cp Sources/Info.plist "$app/Contents/Info.plist"

    icon=Sources/Assets.xcassets/AppIcon.appiconset
    iconset=$TMPDIR/AppIcon.iconset
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
      /usr/bin/sips -z $size $size "$icon/icon_512x512.png" --out "$iconset/icon_''${size}x''${size}.png" >/dev/null
      /usr/bin/sips -z $((size * 2)) $((size * 2)) "$icon/icon_512x512@2x.png" --out "$iconset/icon_''${size}x''${size}@2x.png" >/dev/null
    done
    cp "$icon/icon_512x512@2x.png" "$iconset/icon_512x512@2x.png"
    /usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

    printf 'APPL????' > "$app/Contents/PkgInfo"
    ln -s "$app/Contents/Resources/openmessage" $out/bin/openmessage
    runHook postInstall
  '';

  # Sign in postFixup: stdenv's darwin fixup re-signs the Mach-Os it touches,
  # which would break a seal made earlier. /usr/bin tools need __noChroot.
  __noChroot = true;
  postFixup = ''
    /usr/bin/codesign --force --deep --sign - "$out/Applications/OpenMessage.app"
  '';

  meta = {
    description = "Local-first Google Messages client with an MCP server";
    homepage = "https://github.com/xav-ie/rcsd";
    license = lib.licenses.mit;
    mainProgram = "openmessage";
    platforms = lib.platforms.darwin;
  };
}
