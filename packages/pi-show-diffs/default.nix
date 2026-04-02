{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-show-diffs";
  version = "0.2.6";

  src = fetchFromGitHub {
    owner = "xRyul";
    repo = "pi-show-diffs";
    rev = "b3927bd744ff";
    hash = "sha256-gHwuAZyBCQQ2kYNwXLYjYSMwQgmc+kaNuvMc4mJu9yk=";
  };

  npmDepsHash = "sha256-DwEvcuW+yW1S88ZuMZpMS40ZhtE0XqAU0cg5c77kyEM=";

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
