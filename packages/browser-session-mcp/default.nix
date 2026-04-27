{
  lib,
  stdenv,
  nodejs,
  pnpm,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeBinaryWrapper,
}:
let
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./pnpm-lock.yaml
      ./tsconfig.json
      ./src
      ./scripts
    ];
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "browser-session-mcp";
  inherit version src;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 2;
    hash = "sha256-Jturqhx4AwfYiBFcffDN44h/3FPhzE4ybzzrB8/Cl4A=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    makeBinaryWrapper
  ];

  # pnpmConfigHook stages pnpmDeps into the offline store and runs
  # `pnpm install --offline` during configurePhase.

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/browser-session-mcp $out/bin
    cp dist/index.js dist/reaper.js dist/listener.js $out/lib/browser-session-mcp/
    makeBinaryWrapper ${nodejs}/bin/node $out/bin/browser-session-mcp \
      --add-flags "$out/lib/browser-session-mcp/index.js"
    makeBinaryWrapper ${nodejs}/bin/node $out/bin/browser-session-reaper \
      --add-flags "$out/lib/browser-session-mcp/reaper.js"
    makeBinaryWrapper ${nodejs}/bin/node $out/bin/browser-session-listener \
      --add-flags "$out/lib/browser-session-mcp/listener.js"
    runHook postInstall
  '';

  meta = {
    description = "MCP server giving each caller an isolated browser session against a shared persistent Chrome";
    license = lib.licenses.mit;
    mainProgram = "browser-session-mcp";
    platforms = lib.platforms.unix;
  };
})
