{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  runCommand,
}:

let
  upstream-src = fetchFromGitHub {
    owner = "un-ts";
    repo = "toml-tools";
    rev = "prettier-plugin-toml@1.0.1";
    hash = "sha256-jMfykz6DtJFTdJ/g54MhoPlS45JmcCvgs9UwAV0scck=";
  };

  # Create a source that includes the vendored package-lock.json
  src =
    runCommand "prettier-plugin-toml-src"
      {
        inherit upstream-src;
        packageLock = ./package-lock.json;
      }
      ''
        cp -r ${upstream-src}/packages/prettier-plugin-toml $out
        chmod -R +w $out
        cp $packageLock $out/package-lock.json
      '';
in
buildNpmPackage rec {
  pname = "prettier-plugin-toml";
  version = "1.0.1";

  inherit src;

  npmDepsHash = "sha256-9NB53HiEphnWUeFZSu2yBgspQV7l5bjF8REixIkCgZo=";

  # The package is already built (it's pure JS with no build step needed)
  dontNpmBuild = true;

  # Install just the dependencies needed
  npmInstallFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ nodejs ];

  passthru = {
    packageName = pname;
  };

  meta = {
    description = "Prettier TOML plugin - pure JavaScript implementation";
    homepage = "https://github.com/un-ts/toml-tools";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
