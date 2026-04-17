{
  pkgs,
  lib,
  buildNpmPackage,
  fetchurl,
  writeText,
  makeBinaryWrapper,
  nodejs_25,
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

  # Write command to temp file, then send-keys just sources it (". /tmp/cc-0.sh")
  # Avoids passing the long command string through tmux entirely — 1 short send-keys
  # Capture groups use delimiters (not var names) to survive minifier renaming:
  #   \1=result var, \2=condition, \3=truthy fn, \4=falsy fn, \5=pane, \6=command
  sendKeysPatch = ''
    sed -i 's|let \([^=]\+\)=await(\([^?]\+\)?\([^:]\+\):\([^)]\+\))(\["send-keys","-t",\([^,]\+\),\([^,]\+\),"Enter"\])|var _p="/tmp/cc-"+\5.replace(/%/g,"")+".sh";(await import("fs")).writeFileSync(_p,\6+"; rm "+_p);let \1=await(\2?\3:\4)(["send-keys","-t",\5,". "+_p,"Enter"])|g' cli.js
  '';

  # Disable pane border cosmetics (saves 6 tmux round-trips per spawn)
  # Method names are class properties so they survive minification
  disablePaneBordersPatch = ''
    sed -i \
      -e 's|async setPaneBorderColor([^{]*{|&return;|g' \
      -e 's|async setPaneTitle([^{]*{|&return;|g' \
      -e 's|async enablePaneBorderStatus([^{]*{|&return;|g' \
      cli.js
  '';

  # Guard the permission-prompt useEffect against a missing getAppState.
  # Regression in 2.1.111–2.1.113: when a teammate (agent-teams) triggers a
  # permission prompt, the teammate's toolUseContext arrives at the lead's UI
  # without getAppState, crashing the render with:
  #   "q.toolUseContext.getAppState is not a function"
  # Upstream issue: https://github.com/anthropics/claude-code/issues/50051
  # The value is only used for analytics (tengu_tool_use_show_permission_request),
  # so optional-chaining it is safe — worst case the event reports mode=undefined.
  fixGetAppStatePatch = ''
    sed -i 's|toolUseContext\.getAppState()\.toolPermissionContext\.mode|toolUseContext.getAppState?.()?.toolPermissionContext?.mode|g' cli.js
  '';

  # Stub out the npm-view update checker that polls every 30s.
  # The setInterval runs even with CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC set.
  # Replace "npm" with "/bin/true" in the two c4("npm",["view",...) calls so
  # /bin/true runs instead (instant exit 0, empty stdout, no node/npm overhead).
  # The callers handle empty/failed responses gracefully (return null).
  disableNpmViewPatch = ''
    sed -i 's|"npm",\["view"|"/bin/true",["view"|g' cli.js
  '';

  # Eliminate the 200ms post-split-window sleep (no longer needed with paste-buffer)
  # Only matches parameterless functions: function <name>(){return new Promise(...setTimeout...)}
  # This avoids clobbering the general-purpose sleep(ms) utility
  disableSleepPatch = ''
    sed -i 's|function \([^(]*\)(){return new Promise((\([^)]\+\))=>setTimeout(\2,\([^)]\+\)))}|function \1(){return Promise.resolve()}|g' cli.js
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

  # Must match nodejs version used to build the V8 snapshot in common.nix
  nodejs = nodejs_25;

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

    # Speed up agent spawn by pasting commands instead of typing them
    ${sendKeysPatch}

    # Skip pane border decoration and post-creation sleep
    ${disablePaneBordersPatch}
    ${disableSleepPatch}

    # Stub out npm view update check — runs every 30s despite
    # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC being set
    ${disableNpmViewPatch}

    # Fix agent-teams permission-prompt crash (2.1.111–2.1.113 regression)
    ${fixGetAppStatePatch}

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
