{
  firefox-router,
  lib,
  stdenv,
  swift,
}:
# FirefoxRouter.app, the macOS default browser that forwards links to
# firefox-router. Native rather than an AppleScript applet: an applet launched
# with Control held shows its "Press Run to run this script" startup screen,
# which every Ctrl+click on a link did.
stdenv.mkDerivation {
  pname = "firefox-router-app";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    substituteInPlace main.swift --replace-fail "@router@" "${lib.getExe firefox-router}"
    contents="$out/Applications/FirefoxRouter.app/Contents"
    mkdir -p "$contents/MacOS"
    cp Info.plist "$contents/Info.plist"
    swiftc -O main.swift -o "$contents/MacOS/FirefoxRouter"
    runHook postBuild
  '';
  dontInstall = true;
}
