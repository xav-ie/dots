{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-readcache";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "Gurpartap";
    repo = "pi-readcache";
    rev = "v0.2.0";
    hash = "sha256-l8to2Qh2/sv/gxvlfyp5H5zwv1BuHBT1o67a0zYMW9w=";
  };

  npmDepsHash = "sha256-+dsZ+44d/N6H4yUBO1cBp2XGMQq0Psid/kopP2W8QYs=";

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/src
    cp -r node_modules $out/
    cp index.ts $out/
    cp src/*.ts $out/src/
    cp package.json $out/

    runHook postInstall
  '';

  meta = {
    description = "Pi extension that optimizes read tool calls with replay-aware caching";
    homepage = "https://github.com/Gurpartap/pi-readcache";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
