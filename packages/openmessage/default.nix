# OpenMessage: Google Messages (SMS/RCS) over libgm, with a native macOS app
# and an MCP server. Built from main because the last release (v0.2.9) predates
# the opt-in Streamable HTTP MCP transport and the Google self-heal fixes.
# Mirrors macos/build.sh: Go backend in Contents/Resources, Swift app in
# Contents/MacOS, ad-hoc signed; the source Info.plist already carries the
# release identity (com.openmessage.app). Bump `rev` + `hash` + `vendorHash`
# together.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  jitfix,
  signal-cli,
  stdenv,
  swift,
  swiftpm,
  writeShellScript,
}:
let
  # signal-cli runs on JDK 25, which SIGBUSes at startup on nox without jitfix.
  signal-cli-jitfix = writeShellScript "signal-cli" ''
    export DYLD_INSERT_LIBRARIES=${jitfix}/lib/libjitfix.dylib
    exec ${lib.getExe signal-cli} "$@"
  '';

  version = "0.2.9-unstable-2026-10-24";

  src = fetchFromGitHub {
    owner = "MaxGhenis";
    repo = "openmessage";
    rev = "a455f6328784894d0e9c9b060e6e7f5ac1a0fa62";
    hash = "sha256-/2yUPwoBL4gIveqCQWqsXHpMOQMmPtvdpD9yrDMYd2M=";
  };

  backend = buildGoModule {
    pname = "openmessage-backend";
    inherit version src;
    vendorHash = "sha256-ZsnPPaviJhG3Ud49IOGCVzlxdX+SOp6k/BptipS18us=";
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

  sourceRoot = "${src.name}/macos/OpenMessage";

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  # Paths are repo-relative, and sourceRoot is macos/OpenMessage.
  patches = [
    # Main window without a title bar or traffic lights.
    ./hide-title-bar.patch
    # Notifications only fired on stream reconnects: bytes.lines drops the
    # blank line the app waited for before handling each SSE event.
    ./notification-events.patch
  ];
  patchFlags = [ "-p3" ];

  # The app spawns its backend with `serve --web`; also serve MCP over
  # Streamable HTTP at /mcp so the openmessage-mcp agent can bridge it. The
  # backend's environment is only what the launcher sets, so point it at
  # signal-cli directly for the Signal bridge.
  postPatch = ''
    substituteInPlace Sources/BackendLauncherCore.swift \
      --replace-fail 'arguments: ["serve", "--web"],' \
                     'arguments: ["serve", "--web", "--mcp-sse"],' \
      --replace-fail '"OPENMESSAGES_MACOS_NOTIFICATIONS": "0",' \
                     '"OPENMESSAGES_MACOS_NOTIFICATIONS": "0", "OPENMESSAGES_SIGNAL_CLI": "${signal-cli-jitfix}",'
  '';

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
      /usr/bin/sips -z $((size * 2)) $((size * 2)) "$icon/icon_512x512.png" --out "$iconset/icon_''${size}x''${size}@2x.png" >/dev/null
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

  passthru = { inherit backend; };

  meta = {
    description = "Local-first Google Messages, WhatsApp and Signal client with an MCP server";
    homepage = "https://github.com/MaxGhenis/openmessage";
    license = lib.licenses.mit;
    mainProgram = "openmessage";
    platforms = lib.platforms.darwin;
  };
}
