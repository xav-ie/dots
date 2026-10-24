{
  lib,
  buildNpmPackage,
  esbuild,
  makeWrapper,
  nodejs,
  src,
}:
buildNpmPackage {
  pname = "gtm-mcp";
  version = "3.0.6-${src.shortRev or "unstable"}";

  inherit src;

  nativeBuildInputs = [
    esbuild
    makeWrapper
  ];

  npmDepsHash = "sha256-3jKGq+Kkdg6h7zzrlb2t7XQbc7jDH1TMO627o57L2Hc=";

  # Reword each tool's one-line MCP description to match the terms people
  # search with (also drops the itemsPerPage pagination aside, which stays
  # true but isn't part of the new wording).
  patches = [ ./tool-descriptions.patch ];

  # Upstream's postinstall runs tsc for the worker build we don't use.
  npmFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp ${./stdio.ts} src/stdio.ts
    cp ${./check-tools.ts} src/check-tools.ts
  '';

  buildPhase = ''
    runHook preBuild
    esbuild src/stdio.ts --bundle --platform=node --format=cjs --outfile=stdio.cjs
    esbuild src/check-tools.ts --bundle --platform=node --format=cjs --outfile=check-tools.cjs
    runHook postBuild
  '';

  # Fail the build if a tool's reworded MCP description regresses — see
  # check-tools.ts for why it can't just run the stdio.cjs binary directly.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node check-tools.cjs ${./expected-descriptions.json}
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 stdio.cjs $out/lib/gtm-mcp/stdio.cjs
    makeWrapper ${lib.getExe nodejs} $out/bin/gtm-mcp \
      --add-flags $out/lib/gtm-mcp/stdio.cjs
    runHook postInstall
  '';

  meta = {
    description = "Google Tag Manager MCP server (stape-io tools, self-hosted over stdio)";
    homepage = "https://github.com/stape-io/google-tag-manager-mcp-server";
    license = lib.licenses.asl20;
    mainProgram = "gtm-mcp";
  };
}
