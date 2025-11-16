{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
let
  # To update: run `claude-code-update` from the packages/claude-code directory
  sourcesData = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (sourcesData.native) version gcs_bucket sources;

  # Get source info for current system
  sourceInfo =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  src = fetchurl {
    url = "${gcs_bucket}/${version}/${sourceInfo.platform}/claude";
    inherit (sourceInfo) hash;
  };
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version src;

  dontUnpack = true;
  dontBuild = true;
  # Stripping corrupts the bundled binary
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/claude
    chmod +x $out/bin/claude
  '';

  meta = with lib; {
    description = "Claude Code - Anthropic's AI-powered coding assistant CLI";
    homepage = "https://claude.ai";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    maintainers = [ ];
    mainProgram = "claude";
  };
}
