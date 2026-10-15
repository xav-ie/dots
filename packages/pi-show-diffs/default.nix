{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-show-diffs";
  version = "0.2.14";

  src = fetchFromGitHub {
    owner = "xRyul";
    repo = "pi-show-diffs";
    rev = "v0.2.14";
    hash = "sha256-rmpPz2LI2CZH6Om+qXhbbXjhkjvZHvo3oG1KWqfCk0A=";
  };

  npmDepsHash = "sha256-4XA1JKajwuGEk6vRmcNpXDjjwbp7Ogsrrsesi6hfteo=";

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
    description = "Pi extension that adds a diff approval viewer before edit and write tools change files";
    homepage = "https://github.com/xRyul/pi-show-diffs";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
