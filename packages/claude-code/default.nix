{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  socat,
  bubblewrap,
}:
let
  common = import ./common.nix {
    inherit
      lib
      stdenv
      socat
      bubblewrap
      ;
  };

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

  nativeBuildInputs = [ makeBinaryWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/.claude-wrapped
    chmod +x $out/bin/.claude-wrapped
    wrapProgram $out/bin/.claude-wrapped \
      ${common.wrapperArgs} \
      --argv0 claude
    mv $out/bin/.claude-wrapped $out/bin/claude
  '';

  meta = common.meta "Claude Code - Anthropic's AI-powered coding assistant CLI" // {
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
