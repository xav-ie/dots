flakeRoot:
let
  flake = builtins.getFlake (toString flakeRoot);
  system = builtins.currentSystem;
in
flake
// {
  lib = flake.inputs.nixpkgs.lib;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
}
