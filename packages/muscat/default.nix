{
  lib,
  buildNpmPackage,
  muscat-src,
}:
buildNpmPackage {
  pname = "muscat";
  inherit (lib.importJSON "${muscat-src}/package.json") version;
  src = muscat-src;

  npmDepsHash = "sha256-SJwuDGnncOX89qHmS01mM0y5yQ7QXoWvvCbarJoFTUY=";

  # The `build` script gates on `tsgo --noEmit` (via @typescript/native-preview,
  # a dev-only preview toolchain). Skip the type-check and just run the esbuild
  # bundle — assets are baked in at bundle time via build.ts.
  buildPhase = ''
    runHook preBuild
    node_modules/.bin/tsx build.ts
    runHook postBuild
  '';

  # Output is the single self-contained board.html plus an index.html alias so a
  # static server can serve it at `/`.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp dist/board.html $out/board.html
    ln -s board.html $out/index.html
    runHook postInstall
  '';

  meta = {
    description = "Procedural 12×18in medieval board-poster generator (self-contained board.html)";
    homepage = "https://github.com/xav-ie/Muscat";
    platforms = lib.platforms.all;
  };
}
