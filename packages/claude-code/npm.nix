{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  writeText,
  makeBinaryWrapper,
  socat,
  bubblewrap,
}:
let
  common = import ./common.nix { inherit lib stdenv socat bubblewrap; };

  # Read version and hashes from sources.json to stay in sync with native package
  sourcesData = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (sourcesData.npm)
    version
    hash
    npmDepsHash
    packageLockJson
    ;

  # Write the package-lock.json to a file
  packageLockFile = writeText "package-lock.json" packageLockJson;
in
buildNpmPackage rec {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    inherit hash;
  };

  inherit npmDepsHash;

  postPatch = ''
    cp ${packageLockFile} package-lock.json

    # Remove the prepare script that blocks installation
    sed -i '/"prepare":/d' package.json

    # Fix non-portable shebang for NixOS (Chrome native host wrapper)
    # Claude Code hardcodes #!/bin/bash which doesn't exist on NixOS
    sed -i 's|#!/bin/bash|#!/usr/bin/env bash|g' cli.js
  '';

  dontNpmBuild = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  postFixup = ''
    wrapProgram $out/bin/claude \
      ${common.wrapperArgs}
  '';

  meta = common.meta "Claude Code - Anthropic's AI-powered coding assistant CLI (NPM version)" // {
    platforms = lib.platforms.all;
  };
}
