{
  pkgs,
  lib,
  buildNpmPackage,
  fetchurl,
  writeText,
  makeBinaryWrapper,
}:
let
  common = import ./common.nix { inherit pkgs; };

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

    # Fix dotfile leak: sandbox mounts /dev/null on non-existent deny paths,
    # creating empty files on host. Remove the push, keep the log.
    # See: https://github.com/anthropics/claude-code/issues/17087
    # See: https://github.com/anthropic-experimental/sandbox-runtime/pull/91
    substituteInPlace cli.js \
      --replace-fail \
        'H.push("--ro-bind","/dev/null",j),T8(`[Sandbox Linux] Mounted /dev/null at ''${j} to block creation of ''${_}`)' \
        'T8(`[Sandbox Linux] Skipping non-existent deny path: ''${_}`)'
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
