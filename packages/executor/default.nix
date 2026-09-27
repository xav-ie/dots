{
  pkgs,
  lib,
  stdenvNoCC,
  stdenv,
  autoPatchelfHook,
  makeBinaryWrapper,
  fetchpatch,
  executor-src,
}:
let
  inherit ((lib.importJSON "${executor-src}/apps/cli/package.json")) version;

  # Fixed-output derivation for bun install (needs network access).
  # Follows the OpenCode pattern (github:sst/opencode/nix/node_modules.nix).
  node_modules = stdenvNoCC.mkDerivation {
    pname = "executor-node-modules";
    inherit version;

    src = executor-src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [ pkgs.bun ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress
      bun --bun ${./scripts/canonicalize-node-modules.ts}
      bun --bun ${./scripts/normalize-bun-binaries.ts}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      find . -type d -name node_modules -exec cp -R --parents {} $out \;
      runHook postInstall
    '';

    dontFixup = true;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-c2H5cIbeFOIoSHMoVd5+MDR4r4Kn7MM8G2+kAzNuJ3U=";
  };
in
stdenv.mkDerivation {
  pname = "executor";
  inherit version;
  src = executor-src;
  inherit node_modules;

  # From github:xav-ie/executor; neither touches bun.lock, so node_modules above
  # is shared with upstream.
  patches = [
    # tools.search ranks by query coverage instead of dropping partial matches,
    # and matches a tool's `_meta["executor/integrations"]` (set by snippet-mcp).
    (fetchpatch {
      url = "https://github.com/xav-ie/executor/commit/f8de858b36aeb40704336ce009ff76808dae3ae6.patch";
      hash = "sha256-/ZSLMUhZlANUOF1E8Sseel51oioBjTxSkZ8m1EVl4/o=";
    })
    # Opt-in JSONL log of searches and tool calls (EXECUTOR_USAGE_LOG).
    (fetchpatch {
      url = "https://github.com/xav-ie/executor/commit/98951296bd5c90a25cc1d77ff2c07c153a313a81.patch";
      hash = "sha256-Of7LN3Zy0NQ1V683oNajiQGxBuemveHKdLMz1CkfGz8=";
    })
  ];

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs # for patchShebangs
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = [ stdenv.cc.cc.lib ];

  # Stripping corrupts Bun-compiled binaries
  dontStrip = true;

  configurePhase = ''
    runHook preConfigure

    # Overlay pre-fetched node_modules onto the source tree
    chmod -R u+w .
    cp -R --no-clobber ${node_modules}/. . || true
    chmod -R u+w .

    patchShebangs node_modules
    patchShebangs apps/*/node_modules
    patchShebangs packages/*/node_modules

    runHook postConfigure
  '';

  postPatch = ''
    # bunx tries to resolve from the registry even in sandbox.
    # Use bun --bun to invoke vite with Bun's runtime (needed for TS resolution).
    substituteInPlace apps/local/package.json \
      --replace-fail 'bunx --bun vite' 'bun --bun node_modules/.bin/vite'
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR

    bun run --cwd apps/cli build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/executor
    cp -R apps/cli/dist/executor-linux-x64/bin/. $out/lib/executor/
    chmod +x $out/lib/executor/executor

    makeBinaryWrapper $out/lib/executor/executor $out/bin/executor

    runHook postInstall
  '';

  meta = {
    description = "Local AI executor with a CLI, local API server, and web UI";
    homepage = "https://github.com/RhysSullivan/executor";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "executor";
  };
}
