{ stdenv }:
stdenv.mkDerivation {
  pname = "menubar-reveal";
  version = "0.1.0";
  src = ./menubar-reveal.c;
  dontUnpack = true;
  buildPhase = ''
    runHook preBuild
    $CC -O2 -o menubar-reveal $src -framework CoreGraphics -framework CoreFoundation
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 menubar-reveal $out/bin/menubar-reveal
    runHook postInstall
  '';
  meta.mainProgram = "menubar-reveal";
}
