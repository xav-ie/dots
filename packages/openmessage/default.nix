# OpenMessage, cut over to rcsd: a private fork of MaxGhenis/openmessage
# stripped to Google Messages (SMS/RCS) only. Every fix that used to live in
# the patch pile below is committed upstream in the fork (branch main), so
# this file is down to a source pin. The fork also carries the native macOS
# app (mirrors macos/build.sh: Go backend in Contents/Resources, Swift app in
# Contents/MacOS, ad-hoc signed). Bump `rev` + `vendorHash` together.
#
# The repo is private: fetched over ssh with the invoking user's key
# (builtins.fetchGit is impure on purpose — switch needs key access).
{
  lib,
  buildGoModule,
  stdenv,
  swift,
  swiftpm,
}:
let
  version = "unstable-2026-10-29";

  src = builtins.fetchGit {
    url = "git@github.com:xav-ie/rcsd.git";
    ref = "main";
    rev = "a1952a87aa117340d2ad3cc0a987d43c22afa833";
  };

  backend = buildGoModule {
    pname = "openmessage-backend";
    inherit version src;
    vendorHash = "sha256-c0DFcF6PUGqyerOkzTMgyIpHtgj0dF+D6erVNZKi6Hs=";
    subPackages = [ "." ];
    env.CGO_ENABLED = 0;
    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];
    # Tests drive live sessions and Playwright.
    doCheck = false;
  };
in
stdenv.mkDerivation {
  pname = "openmessage";
  inherit version src;

  # Directory sources are copied to ./<hash-stripped name>; fetchGit names
  # its output "source", like fetchFromGitHub did before the cutover.
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
    cp ${backend}/bin/openmessage "$app/Contents/Resources/openmessage"
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

  passthru = {
    inherit backend;
  };

  meta = {
    description = "Local-first Google Messages client with an MCP server";
    homepage = "https://github.com/xav-ie/rcsd";
    license = lib.licenses.mit;
    mainProgram = "openmessage";
    platforms = lib.platforms.darwin;
  };
}
