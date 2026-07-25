{
  apple-sdk,
  darwin,
  lib,
  stdenv,
}:
# Lets each GUI app flip its own windows out of screen capture
# (bails only for non-app processes with no bundle id). Visible by
# default; the menubar's Screenshare Mode broadcasts the hide. Runtime reveal/hide is
# driven by distributed notifications from the hidewin menubar app / CLI.
stdenv.mkDerivation {
  pname = "hide-windows";
  version = "0-unstable-2026-07-23";

  # Source-scope to just the .m so default.nix edits don't bust the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./HideWindows.m;
  };

  buildInputs = [ apple-sdk ];
  nativeBuildInputs = [ darwin.sigtool ];

  buildPhase = ''
    runHook preBuild
    clang -arch arm64e -arch x86_64 -dynamiclib -framework AppKit \
      -o HideWindows.dylib HideWindows.m
    codesign -f -s - HideWindows.dylib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 HideWindows.dylib $out/lib/HideWindows.dylib
    runHook postInstall
  '';

  meta = {
    description = "Flip apps' windows out of screen capture on demand (Invisiwind for macOS; Screenshare Mode)";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
