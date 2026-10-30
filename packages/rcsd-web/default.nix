# rcsd-web: the static web client for rcsd, an Astro site. The package is its
# dist/ (index.html plus hashed /_astro/* assets), served at the domain root
# by the rcsd-web container (modules/nixos/rcsd.nix). Source is the
# `rcsd-web-src` flake input; bump it and the pnpmDeps hash together.
{
  lib,
  stdenvNoCC,
  fetchPnpmDeps,
  nodejs_24,
  pnpm_10,
  pnpmConfigHook,
  src,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rcsd-web";
  version = "0-unstable-${builtins.substring 0 8 src.lastModifiedDate}";
  inherit src;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-kElpi/yi9u84MRa02gd7M9QiTD8i06TWHdyXAPdtOB8=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_10
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';

  meta = {
    description = "Static web client for the rcsd Google Messages backend";
    platforms = lib.platforms.all;
  };
})
