# Clippy checks for the buildRustPackage outputs in `config.packages`.
{ inputs, ... }:
{
  perSystem =
    {
      config,
      lib,
      system,
      ...
    }:
    let
      defaultClippy = inputs.nixpkgs.legacyPackages.${system}.clippy;

      mkClippyCheck =
        pkg:
        pkg.overrideAttrs (old: {
          pname = "clippy-${old.pname}";
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ (pkg.passthru.clippy or defaultClippy) ];
          buildPhase = ''
            runHook preBuild
            cargo clippy --all-targets --all-features -- -D warnings
            runHook postBuild
          '';
          doCheck = false;
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            runHook postInstall
          '';
        });
    in
    {
      checks = lib.mapAttrs' (name: pkg: lib.nameValuePair "clippy-${name}" (mkClippyCheck pkg)) (
        lib.filterAttrs (_: pkg: pkg ? cargoDeps && !(pkg.passthru.skipClippy or false)) config.packages
      );
    };
}
