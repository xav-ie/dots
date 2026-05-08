{
  apple-sdk,
  darwin,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "pin-iphone-mirroring";
  version = "0-unstable-2026-05-06";

  # Source-scope to just the .m file so edits to default.nix don't bust
  # the source hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./IPhoneMirroringPin.m;
  };

  buildInputs = [ apple-sdk ];
  nativeBuildInputs = [ darwin.sigtool ];

  buildPhase = ''
    runHook preBuild
    clang -arch arm64e -arch x86_64 -dynamiclib -framework AppKit \
      -o IPhoneMirroringPin.dylib IPhoneMirroringPin.m
    codesign -f -s - IPhoneMirroringPin.dylib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 IPhoneMirroringPin.dylib $out/lib/IPhoneMirroringPin.dylib
    runHook postInstall
  '';

  meta = {
    description = "Pin macOS iPhone Mirroring's window to NSFloatingWindowLevel so it stays on top";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
