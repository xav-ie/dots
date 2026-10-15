# Live dictation into scribe, bundled into a gjs binary with AGS (Astal). A
# resident daemon (the `dictate` systemd user service) driven by Hyprland's
# super+g press/release binds: it records with pw-record, streams to scribe's
# WebSocket, and types through hyprctl (send_shortcut). See session.ts.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  glib-networking,
  hyprland,
  lib,
  libsoup_3,
  pipewire,
  wl-clipboard,
  # System UI font, threaded in from lib/fonts.nix.
  fontName,
}:
stdenv.mkDerivation {
  name = "dictate";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss --replace-fail "@FONT@" "${fontName}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
  ];

  # libsoup for the WebSocket, glib-networking for its TLS (wss).
  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
    glib-networking
    libsoup_3
  ];

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : "${
      lib.makeBinPath [
        hyprland
        pipewire
        wl-clipboard
      ]
    }")
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/dictate
    runHook postInstall
  '';
}
