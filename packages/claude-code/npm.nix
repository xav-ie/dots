{
  pkgs,
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  nodejs_25,
  nushell,
  bun-demincer-src,
}:
let
  common = import ./common.nix { inherit pkgs; };

  sourcesData = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (sourcesData.npm) version sources;

  sourceInfo =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  # npm publishes one tarball per platform; the native binary is at `package/claude`.
  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${sourceInfo.platform}/-/claude-code-${sourceInfo.platform}-${version}.tgz";
    inherit (sourceInfo) hash;
  };

  splicer = ./splice.nu;

  # How to fix agent tmux panes when default-shell is non-POSIX (e.g. nushell)
  #   "split-window" - patch split-window to use a POSIX shell wrapper (fast, cleanest)
  #   "nushell"      - patch shell syntax for nushell compatibility (fragile)
  patchMethod = "split-window";

  # Force agent panes to use a POSIX shell with env vars pre-set.
  splitWindowPatch = ''
    sed -i 's|"split-window",\([^]]*\)"#{pane_id}"\]|"split-window",\1"#{pane_id}","${common.spawnWrapper}"]|g' cli.js
  '';

  # Write command to temp file, then send-keys just sources it (". /tmp/cc-0.sh")
  # Avoids passing the long command string through tmux entirely — 1 short send-keys
  # Capture groups use delimiters (not var names) to survive minifier renaming:
  #   \1=result var, \2=condition, \3=truthy fn, \4=falsy fn, \5=pane, \6=command
  sendKeysPatch = ''
    sed -i 's|let \([^=]\+\)=await(\([^?]\+\)?\([^:]\+\):\([^)]\+\))(\["send-keys","-t",\([^,]\+\),\([^,]\+\),"Enter"\])|var _p="/tmp/cc-"+\5.replace(/%/g,"")+".sh";(await import("fs")).writeFileSync(_p,\6+"; rm "+_p);let \1=await(\2?\3:\4)(["send-keys","-t",\5,". "+_p,"Enter"])|g' cli.js
  '';

  # Disable pane border cosmetics (saves 6 tmux round-trips per spawn).
  # Method names are class properties so they survive minification.
  disablePaneBordersPatch = ''
    sed -i \
      -e 's|async setPaneBorderColor([^{]*{|&return;|g' \
      -e 's|async setPaneTitle([^{]*{|&return;|g' \
      -e 's|async enablePaneBorderStatus([^{]*{|&return;|g' \
      cli.js
  '';

  # Stub out the npm-view update checker that polls every 30s.
  # Replace "npm" with "/bin/true" so it exits 0 immediately with empty stdout.
  disableNpmViewPatch = ''
    sed -i 's|"npm",\["view"|"/bin/true",["view"|g' cli.js
  '';

  # "nushell": patch POSIX syntax that nushell doesn't handle.
  nushellPatch = ''
    sed -i '/CLAUDECODE=1/s| && | ; |g' cli.js
    sed -i 's|;<=>?@\[|;<=>?\[|g' cli.js
  '';

  # Patches that became obsolete with claude-code 2.1.114:
  #   #!/bin/bash shebang — upstream removed the Chrome native-host wrapper
  #   disableSleepPatch — upstream inlined/restructured the sleep helper
  #   fixGetAppStatePatch — upstream merged the optional-chain fix
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version src;

  # The npm tarball unpacks to ./package/claude — let stdenv handle unpacking.
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    nodejs_25
    nushell
  ]
  ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall

    # Stdenv unpacked the tarball to ./package/. Copy out the native binary.
    cp claude claude-original
    chmod +w claude-original

    # 1. Extract cli.js + native modules from the Bun-compiled binary.
    mkdir extracted
    node ${bun-demincer-src}/src/extract.mjs claude-original extracted
    cp extracted/src/entrypoints/cli.js cli.js
    chmod +w cli.js

    # 2. Apply patches in-place.
    ${if patchMethod == "split-window" then splitWindowPatch else nushellPatch}
    ${sendKeysPatch}
    ${disablePaneBordersPatch}
    ${disableNpmViewPatch}

    # 3. Splice patched cli.js back into the Bun binary (drops the JSC
    #    bytecode cache — Bun re-parses at startup, ~100 ms slower).
    mkdir -p "$out/bin"
    nu ${splicer} claude-original cli.js "$out/bin/.claude-wrapped"
    chmod +x "$out/bin/.claude-wrapped"

    # 4. Wrap with env vars and PATH (shared with the native package).
    wrapProgram "$out/bin/.claude-wrapped" \
      ${common.wrapperArgs} \
      --argv0 claude
    mv "$out/bin/.claude-wrapped" "$out/bin/claude"

    runHook postInstall
  '';

  meta = common.meta "Claude Code - patched Bun binary (tmux spawn perf, no auto-update polling)" // {
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
