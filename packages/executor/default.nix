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
  inherit ((lib.importJSON "${executor-src}/apps/cli/package.json")) version;

  # Fixed-output derivation for bun install (needs network access).
  # Follows the OpenCode pattern (github:sst/opencode/nix/node_modules.nix).
  #
  # Unlike v1, this does NOT pass --ignore-scripts: v2's package.json scopes
  # lifecycle scripts to `trustedDependencies` (dugite, electron*, esbuild,
  # workerd) itself, and workerd's postinstall is what places its platform
  # binary at node_modules/workerd/bin/workerd. Running with scripts enabled
  # is the project's own default, not a departure from it.
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
    outputHash = "sha256-4FE2VGh1viowmUeBaeKYkyEbAlNT1FqfkypaKk8QYhU=";
  };

  # packages/telemetry's build clones a separate pinned repo (Motel, a
  # workerd-based telemetry collector) and runs its own `bun install` against
  # its own lockfile (packages/telemetry/motel/source.json pins the revision).
  # That needs network, so it is its own fixed-output derivation, built the
  # same way as the real `bun run telemetry:build` would, instead of a
  # hand-written re-implementation of scripts/build-motel.ts.
  motelDist = stdenvNoCC.mkDerivation {
    pname = "executor-motel-dist";
    inherit version;

    src = executor-src;
    inherit node_modules;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      pkgs.bun
      pkgs.nodejs
      pkgs.git
      pkgs.cacert
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

      chmod -R u+w .
      cp -R --no-clobber ${node_modules}/. . || true
      chmod -R u+w .
      patchShebangs node_modules

      bun run telemetry:build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -R packages/telemetry/dist/motel $out
      runHook postInstall
    '';

    dontFixup = true;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-x/maF4g3837Dzjp2W6rpLgfe94cr1UcXB1+4uwghHDI=";
  };
in
stdenv.mkDerivation {
  pname = "executor";
  inherit version;
  src = executor-src;
  inherit node_modules;

  postPatch = ''
    # build-motel.ts always clones and rebuilds Motel from its pinned repo,
    # which needs network. motelDist (above) already built it as its own
    # fixed-output derivation; skip the clone/rebuild here when its output is
    # already in place.
    substituteInPlace packages/telemetry/scripts/build-motel.ts \
      --replace-fail \
        'const output = path.join(root, "dist/motel");' \
        'const output = path.join(root, "dist/motel"); if (yield* fs.exists(output)) return yield* Effect.logInfo("Reusing prebuilt Motel at " + output);'
  '';

  # tools.search patches from feat/v2-search-patches, exported as local
  # git-format-patch files (not fetchpatch: nothing here is pushed yet).
  # Neither touches bun.lock, so node_modules above stays keyed on the
  # unpatched source.
  patches = [
    # tools.search ranks by embedding vectors kept in side tables when EXECUTOR_EMBED_URL is set.
    ./patches/0001-embedding-search.patch
    # Opt-in JSONL log of searches and tool calls (EXECUTOR_USAGE_LOG).
    ./patches/0002-usage-log.patch
    # Hide the dashboard apps, which re-mount other apps' tools, from unscoped tools.search.
    ./patches/0003-search-exclude-apps.patch
  ];

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs # patchShebangs, and `npm pack` used by scripts/releases/package.ts
    pkgs.git # telemetry:build's build-motel.ts shells out to `git init`
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = [
    stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.curl
    pkgs.expat
    pkgs.fontconfig
  ];

  # Stripping corrupts Bun-compiled binaries
  dontStrip = true;

  configurePhase = ''
    runHook preConfigure

    # Overlay pre-fetched node_modules onto the source tree
    chmod -R u+w .
    cp -R --no-clobber ${node_modules}/. . || true
    chmod -R u+w .

    patchShebangs node_modules
    for dir in $(find . -mindepth 2 -maxdepth 4 -type d -name node_modules); do
      patchShebangs "$dir"
    done

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR

    # Mirrors scripts/releases/package.ts's own build order (RELEASING.md,
    # "Build and verify"). EXECUTOR_BUN_RUNTIME is deliberately left unset:
    # the project's own fallback builds the standalone executable on stock
    # Bun, logging that this is a development build rather than a signed
    # release build. That is the right trade for a self-built package.
    # scripts/releases/package.ts (release:cli) runs apps:build, telemetry:build
    # and web:build itself before assembling the standalone executable; only
    # telemetry:build's Motel clone needs pre-seeding (see postPatch above).
    mkdir -p packages/telemetry/dist
    cp -R ${motelDist} packages/telemetry/dist/motel
    chmod -R u+w packages/telemetry/dist/motel

    # package.ts spawns the bundled Git (dugite) at build time, to verify it
    # works, before autoPatchelfHook's normal fixup pass would patch it.
    autoPatchelf node_modules/dugite/git

    node scripts/releases/package.ts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    standalone=.local/releases/${version}-linux-x64/standalone
    mkdir -p $out/bin $out/lib/executor
    cp -R "$standalone"/. $out/lib/executor/
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
