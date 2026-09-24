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
  # means the tarball binary is installed as-is, skipping extract + splice.
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
  # every patch is checked: no JS module changed fails the build.
  applyPatches =
    patches
    |> lib.concatMapStringsSep "\n" (
      p: # sh
      ''
        cp -a extracted extracted.pre
        (cd extracted && sed -i ${p.args} $targets)
        if diff -rq extracted extracted.pre > /dev/null; then
          echo "claude-code patch '${p.name}' matched nothing — upstream shape changed"
          exit 1
        fi
        rm -rf extracted.pre
      ''
    );

  splicePatched = # sh
    ''
      # 1. Extract every JS module from the Bun-compiled binary. Upstream
      #    code-splits, so a patch target can live in any chunk, not just
      #    the entry module.
      mkdir extracted
      node ${bun-demincer-src}/src/extract.mjs claude-original extracted
      cp -a extracted extracted.orig
      targets=$(cd extracted && { ls *.js; node -p 'require("./manifest.json").entryPoint.split("/").pop()'; } | sort -u)

      # 2. Apply patches in-place across all JS modules.
      ${applyPatches}

      # 3. Splice the modules that actually changed back into the Bun binary.
      #    Only those modules lose their JSC bytecode cache and get re-parsed
      #    at launch; the rest of the CLI still starts from cache.
      changed=$(cd extracted && for f in $targets; do cmp -s "$f" "../extracted.orig/$f" || echo "$f"; done)
      nu ${splicer} claude-original extracted "$out/bin/.claude-wrapped" $changed
    '';

  installBinary =
    if patches == [ ] then ''cp claude-original "$out/bin/.claude-wrapped"'' else splicePatched;
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
    ${installBinary}
    chmod +x "$out/bin/.claude-wrapped"

    # splice.nu edits bytes inside the __BUN segment, so segment offsets stay
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
