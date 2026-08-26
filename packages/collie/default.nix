# Collie — phone web UI for the herd, built from source.
#
# Upstream expects `herdr plugin install`, whose scripts/collie-ctl.sh clones,
# runs `bun install`, builds the web UI and writes its own systemd unit. None of
# that is used: the tree is built here and driven by env vars from
# modules/collie.nix, since bridge/config.ts reads every setting from
# process.env.
#
# `bun install` needs the network, so dependencies come from a fixed-output
# derivation. The two committed bun.lock files pin the versions;
# --frozen-lockfile refuses to deviate.
#
# The bridge resolves paths relative to its own directory (`import.meta.dir/..`),
# so the whole tree ships together — bridge, built web/dist and package.json.
{
  lib,
  bun,
  cacert,
  fetchFromGitHub,
  makeWrapper,
  stdenvNoCC,
}:
let
  version = "0-unstable-2026-08-26";

  src = fetchFromGitHub {
    owner = "AltanS";
    repo = "collie";
    rev = "10ad046633bce25d95333f058139c31dbb232b2d";
    hash = "sha256-KRHlfWOOmRPtQQMi4gw98gOhVoCXGLKrjuuOnGAi2e8=";
  };

  deps = stdenvNoCC.mkDerivation {
    pname = "collie-deps";
    inherit version src;

    nativeBuildInputs = [ bun ];

    dontConfigure = true;

    # patchShebangs would rewrite dependency scripts to store paths, and a
    # fixed-output derivation may not contain references to the store.
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      export HOME="$NIX_BUILD_TOP"
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

      bun install --frozen-lockfile --no-progress
      cd web && bun install --frozen-lockfile --no-progress

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r "$NIX_BUILD_TOP/source/node_modules" $out/node_modules
      cp -r "$NIX_BUILD_TOP/source/web/node_modules" $out/web-node_modules
      runHook postInstall
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-cK/Z6KWufZwnl1C5s2DPC5wUgZg2aCrfvmuaRfkRLUY=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "collie";
  inherit version src;

  nativeBuildInputs = [
    bun
    makeWrapper
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$NIX_BUILD_TOP"
    cp -r ${deps}/node_modules node_modules
    cp -r ${deps}/web-node_modules web/node_modules
    chmod -R u+w node_modules web/node_modules

    # Only the UI bundle; upstream's `build` script also typechecks, which needs
    # a writable bunx cache and adds nothing to the artifact. Vite is invoked by
    # path rather than through node_modules/.bin, whose `#!/usr/bin/env node`
    # shebang has no /usr/bin/env to resolve against in the sandbox.
    (cd web && bun node_modules/vite/bin/vite.js build)

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/collie
    cp -r bridge node_modules package.json $out/share/collie/
    mkdir -p $out/share/collie/web
    cp -r web/dist $out/share/collie/web/dist

    makeWrapper ${lib.getExe bun} $out/bin/collie-bridge \
      --add-flags "run $out/share/collie/bridge/index.ts"

    runHook postInstall
  '';

  meta = {
    description = "Phone web UI for a herdr agent herd";
    homepage = "https://github.com/AltanS/collie";
    license = lib.licenses.mit;
    mainProgram = "collie-bridge";
    platforms = lib.platforms.unix;
  };
}
