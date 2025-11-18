{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  runCommand,
  prettier,
}:

let
  prettier-plugin-toml = import ./plugin {
    inherit
      lib
      buildNpmPackage
      fetchFromGitHub
      nodejs
      runCommand
      ;
  };
in
prettier.override {
  plugins = [ prettier-plugin-toml ];
}
