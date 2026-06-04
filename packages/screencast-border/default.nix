# Screen-share border overlay, bundled into a gjs binary with AGS (Astal). A
# resident daemon (see home-manager/linux/screencast-border) that frames every
# monitor in red while a screencast is live and offers an inline "Stop sharing"
# pill. Detection and the stop action both shell out to pipewire (pw-mon/pw-cli).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  pipewire,
  agsPackages,
  # System UI font for the "Stop sharing" pill (@FONT@ in style.scss), threaded
  # in from lib/fonts.nix so it tracks the same `sans` font as the rest of GTK.
  fontName,
}:
stdenv.mkDerivation {
  name = "screencast-border";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss --replace-fail "@FONT@" "${fontName}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
  ];

  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
  ];

  # pw-mon (detection) and pw-cli (stop) are invoked by name at runtime.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ pipewire ]})
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/screencast-border
    runHook postInstall
  '';
}
