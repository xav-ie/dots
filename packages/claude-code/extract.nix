{
  lib,
  stdenv,
  fetchurl,
  nodejs_25,
  bun-demincer-src,
}:
let
  sourcesData = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (sourcesData.native) version gcs_bucket sources;

  sourceInfo =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  src = fetchurl {
    url = "${gcs_bucket}/${version}/${sourceInfo.platform}/claude";
    inherit (sourceInfo) hash;
  };
in
stdenv.mkDerivation {
  pname = "claude-code-extract";
  inherit version src;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ nodejs_25 ];

  installPhase = ''
    runHook preInstall

    cp "$src" claude-binary
    chmod +w claude-binary

    mkdir -p "$out"
    node ${bun-demincer-src}/src/extract.mjs claude-binary "$out"

    runHook postInstall
  '';

  meta = {
    description = "Extracted JavaScript/native modules from the claude-code Bun binary";
    homepage = "https://github.com/vicnaum/bun-demincer";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
