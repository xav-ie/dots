{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  writeText,
  makeBinaryWrapper,
  socat,
  bubblewrap,
}:
let
  # Read version and hashes from sources.json to stay in sync with native package
  sourcesData = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (sourcesData.npm)
    version
    hash
    npmDepsHash
    packageLockJson
    ;

  # Write the package-lock.json to a file
  packageLockFile = writeText "package-lock.json" packageLockJson;
in
buildNpmPackage rec {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    inherit hash;
  };

  inherit npmDepsHash;

  postPatch = ''
    cp ${packageLockFile} package-lock.json

    # Remove the prepare script that blocks installation
    sed -i '/"prepare":/d' package.json
  '';

  dontNpmBuild = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  postFixup = ''
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.isLinux "--prefix PATH : ${
        lib.makeBinPath [
          socat
          bubblewrap
        ]
      }"}
  '';

  meta = with lib; {
    description = "Claude Code - Anthropic's AI-powered coding assistant CLI (NPM version)";
    homepage = "https://claude.ai";
    license = licenses.unfree;
    platforms = platforms.all;
    maintainers = [ ];
    mainProgram = "claude";
  };
}
