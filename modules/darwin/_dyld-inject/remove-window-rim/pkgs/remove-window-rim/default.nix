{
  apple-sdk,
  darwin,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "remove-window-rim";
  version = "0-unstable-2026-05-06";

  # Source-scope to just the .m file so edits to default.nix don't bust
  # the source hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./RemoveWindowRim.m;
  };

  buildInputs = [ apple-sdk ];
  nativeBuildInputs = [ darwin.sigtool ];

  buildPhase = ''
    runHook preBuild
    clang -arch arm64e -arch x86_64 -dynamiclib -framework AppKit \
      -o RemoveWindowRim.dylib RemoveWindowRim.m
    codesign -f -s - RemoveWindowRim.dylib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 RemoveWindowRim.dylib $out/lib/RemoveWindowRim.dylib
    runHook postInstall
  '';

  meta = {
    description = "Zero NSWindow.shadowParameters rim keys to kill macOS Tahoe's 1px Liquid Glass window border";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
