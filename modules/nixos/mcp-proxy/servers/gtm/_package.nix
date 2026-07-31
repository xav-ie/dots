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

  # Upstream's postinstall runs tsc for the worker build we don't use.
  npmFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp ${./stdio.ts} src/stdio.ts
  '';

  buildPhase = ''
    runHook preBuild
    esbuild src/stdio.ts --bundle --platform=node --format=cjs --outfile=stdio.cjs
    runHook postBuild
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
