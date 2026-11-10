# Resident "Insert / Touch your YubiKey" popup for the Linux desktop, bundled
# into a gjs binary with AGS (Astal) like askpass. Run as a user service by
# modules/nixos/sudo-yubikey.nix.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  # System UI font, threaded in from lib/fonts.nix (@FONT@ in style.scss).
  fontName,
}:
stdenv.mkDerivation {
  name = "yubikey-touch-popup";
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
    ags bundle app.ts $out/bin/yubikey-touch-popup
    runHook postInstall
  '';

  meta.mainProgram = "yubikey-touch-popup";
}
