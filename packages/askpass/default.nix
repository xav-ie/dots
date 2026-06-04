# Standalone SUDO_ASKPASS helper, bundled into a gjs binary with AGS (Astal).
# sudo runs `askpass <prompt>`; it shows a keyboard-exclusive password prompt and
# prints the typed password to stdout (exit 0), or exits non-zero on
# cancel/timeout. Replaces the zenity helper; wired in
# nixosConfigurations/modules/sudo-askpass.nix.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  # System UI font, threaded in from lib/fonts.nix so the prompt tracks the same
  # `sans` font as the rest of the GTK config (@FONT@ in style.scss).
  fontName,
}:
stdenv.mkDerivation {
  name = "askpass";
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
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/askpass
    runHook postInstall
  '';
}
