{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  yarn-berry_3,
}:

let
  yarn-berry = yarn-berry_3;
  pname = "prettier-plugin-toml";
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname;
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "un-ts";
    repo = "toml-tools";
    rev = "prettier-plugin-toml@${finalAttrs.version}";
    hash = "sha256-jMfykz6DtJFTdJ/g54MhoPlS45JmcCvgs9UwAV0scck=";
  };

  nativeBuildInputs = [
    nodejs
    yarn-berry.yarnBerryConfigHook
  ];

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src;
    hash = "sha256-WOOGoUQgd1YUau78vLvH44bD0G7GompKnDZPZ4x1ZJA=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -r ./* $out/lib

    runHook postInstall
  '';

  passthru = {
    packageName = pname;
  };

  meta = {
    description = "Prettier TOML plugin - pure JavaScript implementation";
    homepage = "https://github.com/un-ts/toml-tools";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
})
