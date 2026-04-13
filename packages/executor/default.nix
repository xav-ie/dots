{
  pkgs,
  lib,
  stdenvNoCC,
  stdenv,
  autoPatchelfHook,
  makeBinaryWrapper,
  executor-src,
}:
let
  version = "1.4.5";

  # Hosts the executor web server will accept connections from.
  allowedHosts = [
    "localhost"
    "127.0.0.1"
    "[::1]"
    "::1"
    "executor.lalala.casa"
  ];
  allowedHostsJs = lib.concatMapStringsSep ", " (h: ''"${h}"'') allowedHosts;

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
    outputHash = "sha256-RpprUaDcexj/JEKOKHFNtJZ0WldgjtQ54SRNTTHJiok=";
  };
in
stdenv.mkDerivation {
  pname = "executor";
  inherit version;
  src = executor-src;
  inherit node_modules;

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
    # Patch allowed hosts
    substituteInPlace apps/local/src/serve.ts \
      --replace-fail \
        'const ALLOWED_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]", "::1"])' \
        'const ALLOWED_HOSTS = new Set([${allowedHostsJs}])'

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
    cp apps/cli/dist/executor-linux-x64/bin/executor $out/lib/executor/
    cp apps/cli/dist/executor-linux-x64/bin/emscripten-module.wasm $out/lib/executor/
    cp apps/cli/dist/executor-linux-x64/bin/secure-exec-v8 $out/lib/executor/ 2>/dev/null || true
    chmod +x $out/lib/executor/executor $out/lib/executor/secure-exec-v8 2>/dev/null || true

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
