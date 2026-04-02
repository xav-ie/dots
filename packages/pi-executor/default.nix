{
  lib,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-executor";
  version = "1.0.0";

  src = ./.;

  npmDepsHash = "sha256-FSTn1Jv5UyHMni8XPOfdVrr5sqDuVjlReeIKby3qKlY=";

  dontNpmBuild = true;

  # Install the extension files alongside node_modules
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r node_modules $out/
    cp index.ts $out/
    cp package.json $out/

    runHook postInstall
  '';

  meta = {
    description = "Pi coding agent extension for executor MCP server";
    platforms = lib.platforms.all;
  };
}
