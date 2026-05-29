# AGS (Astal) bluetooth picker, bundled into a standalone gjs binary.
# `agsPackages` is inputs.ags.packages.<system>, which re-exports the astal
# libraries (io, astal4, bluetooth) alongside the ags CLI (default).
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  # System UI font family, threaded in from lib/fonts.nix so the picker tracks
  # the same `sans` font as the rest of the GTK config.
  fontName,
}:
stdenv.mkDerivation {
  name = "bluetooth-picker";
  src = ./.;

  postPatch = ''
    substituteInPlace style.scss --replace-fail "@FONT@" "${fontName}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
  ];

  # On GI_TYPELIB_PATH at runtime via the gobject-introspection setup hook.
  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
    agsPackages.bluetooth
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/bluetooth-picker
    runHook postInstall
  '';
}
