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

  # How to fix agent tmux panes when default-shell is non-POSIX (e.g. nushell)
  #   "split-window" - patch split-window to use a POSIX shell wrapper (fast, cleanest)
  #   "nushell"      - patch shell syntax for nushell compatibility (fragile)
  patchMethod = "split-window";

  # "split-window": force agent panes to use a POSIX shell with env vars pre-set
  splitWindowPatch = ''
    sed -i 's|"split-window",\([^]]*\)"#{pane_id}"\]|"split-window",\1"#{pane_id}","${common.spawnWrapper}"]|g' cli.js
  '';

  # "nushell": patch POSIX syntax that nushell doesn't handle
  nushellPatch = ''
    # Replace && with ; on agent spawn lines (identified by CLAUDECODE=1)
    sed -i '/CLAUDECODE=1/s| && | ; |g' cli.js
    # Fix shell-quote escaping @ as \@ (nushell doesn't recognize \@)
    sed -i 's|;<=>?@\[|;<=>?\[|g' cli.js
  '';
in
buildNpmPackage {
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

    # Fix agent tmux panes for non-POSIX default-shell
    ${if patchMethod == "split-window" then splitWindowPatch else nushellPatch}

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
