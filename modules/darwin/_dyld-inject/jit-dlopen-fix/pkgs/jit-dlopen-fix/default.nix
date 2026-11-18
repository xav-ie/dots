{
  apple-sdk,
  darwin,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "jit-dlopen-fix";
  version = "0-unstable-2026-11-13";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./JitDlopenFix.c;
  };

  buildInputs = [ apple-sdk ];
  nativeBuildInputs = [ darwin.sigtool ];

  buildPhase = ''
    runHook preBuild
    clang -arch arm64e -arch x86_64 -dynamiclib -O2 \
      -o JitDlopenFix.dylib JitDlopenFix.c
    codesign -f -s - JitDlopenFix.dylib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 JitDlopenFix.dylib $out/lib/JitDlopenFix.dylib
    runHook postInstall
  '';

  meta = {
    description = "Restore a thread's MAP_JIT write-protect state after dlopen";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
