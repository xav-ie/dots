flakeRoot:
let
  flake = flakeRoot |> toString |> builtins.getFlake;
  system = builtins.currentSystem;
in
flake
// {
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
}
