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
    # Serve signal-cli's Signal group photos (/api/signal/group-avatar) instead
    # of borrowing a member's, and move the platform marker off the avatar to
    # beside the conversation name. The web UI is embedded in this binary.
    # /api/avatar falls back to signal-cli's contact/profile photo by phone,
    # for Signal 1:1s and SMS contacts Google has no photo of. Threads the
    # phone files under Spam & blocked leave Recent for their own tab (and
    # list_conversations unless include_spam); every connect lists that
    # folder so stored threads learn their status.
    patches = [
      ./signal-group-avatars.patch
      ./signal-contact-avatars.patch
      ./spam-blocked-tab.patch
      # Ctrl+Tab / Ctrl+Shift+Tab cycle conversations.
      ./ctrl-tab-conversations.patch
      # Tab moves (Archive, custom tabs) write the v2 store, which v2 reads
      # serve; they only reached the legacy store and failed with "no rows".
      ./v2-conversation-tabs.patch
      # Name people who aren't contacts after their RCS profile ("~name", as
      # Google Messages shows it), read from a Participant field libgm skips.
      ./rcs-profile-names.patch
      # Favorite, notification mode, unread counts, mark-read and People read
      # and write the v2 store; they hit the legacy one and failed or went stale.
      ./v2-conversation-writes.patch
      # Signal threads muted on the phone (signal-cli syncs the mute) read as
      # notification mode "muted" while the mute lasts.
      ./signal-mute.patch
      # Threads archived on the phone get their messages at startup, opening an
      # empty thread fetches its history, and archive syncs both ways.
      ./empty-threads.patch
    ];
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
    # Title notifications from unsaved contacts with their number (SenderName
    # is empty, and an empty title shows the app name), and attach the
    # sender's photo from the backend's synced avatars or Contacts.
    ./notification-sender.patch
    # The WebView reloaded on every SwiftUI update, since its loaded URL never
    # equals baseURL exactly; reload only when the backend's host/port moves.
    ./webview-reload.patch
    # Spam and blocked threads (tab "spam") never notify.
    ./spam-notifications.patch
    # No window tabbing, so Ctrl+Tab reaches the web UI.
    ./ctrl-tab-window.patch
    # Muted threads never notify; "mentions" ones only when mentioned.
    ./mute-notifications.patch
    # A group notification is titled with the group, the sender as subtitle,
    # and shows the group's photo (Signal, WhatsApp) before the sender's.
    ./group-notifications.patch
    # Alert "WhatsApp was logged out" only after WhatsApp was ever paired,
    # not on every launch of an install that never linked it.
    ./whatsapp-alert.patch
    # launchd runs the backend (modules/openmessage.nix); the app only adopts
    # it and leaves it running on quit, never starting a second one.
    ./external-backend.patch
  ];
  patchFlags = [ "-p3" ];

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

  passthru = {
    inherit backend;
    signal-cli = signal-cli-jitfix;
  };

  meta = {
    description = "Local-first Google Messages, WhatsApp and Signal client with an MCP server";
    homepage = "https://github.com/MaxGhenis/openmessage";
    license = lib.licenses.mit;
    mainProgram = "openmessage";
    platforms = lib.platforms.darwin;
  };
}
