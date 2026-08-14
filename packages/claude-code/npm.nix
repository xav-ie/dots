{
  pkgs,
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  nodejs_25,
  nushell,
  rcodesign,
  bun-demincer-src,
}:
let
  common = import ./common.nix { inherit pkgs; };

  sourcesData = ./sources.json |> builtins.readFile |> builtins.fromJSON;
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

  # Add `{ name = "…"; args = "-e 's|…|…|g'"; }` entries to modify the CLI. Empty
  # means the tarball binary is installed as-is: extract + splice would drop the
  # JSC bytecode cache and cost ~390 ms of startup (72 ms -> 467 ms, measured) for
  # no benefit. Any patch has to be worth that on every launch.
  patches = [
    # The vim mode indicator renders as a dim ink Text node:
    #   Vsc=mao?rs.jsxs(_,{dimColor:!0,children:["-- ",E_t," --"]},"vim-indicator"):null
    # Swap dimColor for a per-mode color. Done here rather than in the statusline
    # (via statusLine.hideVimModeIndicator) because the statusline only re-runs on
    # events, so a mode switch there visibly lags; this node re-renders instantly.
    # The mode variable is minified, so it is captured rather than named. Colors
    # are theme names, not ANSI names — this Text component resolves them through
    # the theme (success/error/warning/suggestion/autoAccept/claude/...), and an
    # unknown name like "green" silently falls back to default white.
    {
      name = "vim-mode-colors";
      args = ''-e 's#{dimColor:!0,children:\["-- ",\([A-Za-z_$][A-Za-z0-9_$]*\)," --"\]}#{color:(\1==="INSERT"?"success":\1==="VISUAL"||\1==="VISUAL LINE"?"autoAccept":\1==="REPLACE"?"error":"suggestion"),children:["-- ",\1," --"]}#g' '';
    }
  ];

  # sed against minified upstream silently no-ops once the code shape moves, so
  # every patch is checked: no change to cli.js fails the build.
  applyPatches =
    patches
    |> lib.concatMapStringsSep "\n" (p: ''
      cp cli.js cli.js.pre
      sed -i ${p.args} cli.js
      if cmp -s cli.js.pre cli.js; then
        echo "claude-code patch '${p.name}' matched nothing — upstream shape changed"
        exit 1
      fi
      rm cli.js.pre
    '');
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
  ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ]
  ++ lib.optionals stdenv.isDarwin [ rcodesign ];

  installPhase = ''
    runHook preInstall

    # Stdenv unpacked the tarball to ./package/. Copy out the native binary.
    cp claude claude-original
    chmod +w claude-original

    mkdir -p "$out/bin"
    ${
      if patches == [ ] then
        ''
          cp claude-original "$out/bin/.claude-wrapped"
        ''
      else
        ''
          # 1. Extract cli.js + native modules from the Bun-compiled binary. The
          #    entry module's path inside the Bun VFS moves between releases, so
          #    read it from the manifest instead of hardcoding.
          mkdir extracted
          node ${bun-demincer-src}/src/extract.mjs claude-original extracted
          cp "extracted/$(node -p 'require("./extracted/manifest.json").entryPoint.split("/$bunfs/root/")[1]')" cli.js
          chmod +w cli.js

          # 2. Apply patches in-place.
          ${applyPatches}

          # 3. Splice patched cli.js back into the Bun binary (drops the JSC
          #    bytecode cache — Bun re-parses the 25 MB CLI at every launch,
          #    ~390 ms slower).
          nu ${splicer} claude-original cli.js "$out/bin/.claude-wrapped"
        ''
    }
    chmod +x "$out/bin/.claude-wrapped"

    # splice.nu patches the __BUN segment in-place, so segment offsets stay
    # valid but the original adhoc signature now covers stale bytes. macOS
    # arm64 SIGKILLs binaries with broken signatures, so re-sign with rcodesign.
    ${lib.optionalString (stdenv.isDarwin && patches != [ ]) ''
      rcodesign sign "$out/bin/.claude-wrapped"
    ''}

    # 4. Wrap with env vars and PATH (shared with the native package).
    wrapProgram "$out/bin/.claude-wrapped" \
      ${common.wrapperArgs} \
      --argv0 claude
    mv "$out/bin/.claude-wrapped" "$out/bin/claude"

    runHook postInstall
  '';

  meta = common.meta "Claude Code - npm tarball binary, patchable via the `patches` list" // {
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
