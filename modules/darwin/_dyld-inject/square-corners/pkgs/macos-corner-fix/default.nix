{
  apple-sdk,
  darwin,
  lib,
  stdenv,
  macos-corner-fix-src,
  cornerRadius ? "0.0",
}:
stdenv.mkDerivation {
  pname = "macos-corner-fix";
  version = "0-unstable-2026-04-18";

  src = macos-corner-fix-src;

  buildInputs = [ apple-sdk ];
  nativeBuildInputs = [ darwin.sigtool ];

  # Replace upstream SafariCornerTweak.m with our version. (Rim handling
  # split into the remove-window-rim module; this dylib is corners-only.)
  postPatch = ''
    cp ${./SafariCornerTweak.m} SafariCornerTweak.m
    substituteInPlace SafariCornerTweak.m \
      --replace-fail '___CORNER_RADIUS___' '${cornerRadius}'
  '';

  buildPhase = ''
    runHook preBuild
    clang -arch arm64e -arch x86_64 -dynamiclib -framework AppKit \
      -o SafariCornerTweak.dylib SafariCornerTweak.m
    codesign -f -s - SafariCornerTweak.dylib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 SafariCornerTweak.dylib $out/lib/SafariCornerTweak.dylib
    runHook postInstall
  '';

  meta = {
    description = "Square macOS Tahoe windows by swizzling NSThemeFrame radius getters";
    homepage = "https://github.com/m4rkw/macos-corner-fix";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
