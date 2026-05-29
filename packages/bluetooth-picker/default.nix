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

        install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/bluetooth-picker.svg

        mkdir -p $out/share/applications
        cat > $out/share/applications/bluetooth-picker.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Bluetooth Picker
    Comment=Connect and manage Bluetooth devices
    Exec=$out/bin/bluetooth-picker
    Icon=bluetooth-picker
    Terminal=false
    Categories=Settings;HardwareSettings;
    Keywords=bluetooth;bt;device;pair;connect;
    EOF

        runHook postInstall
  '';
}
