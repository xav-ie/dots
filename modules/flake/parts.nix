# flakeModules.modules (the dendritic `flake.modules.*` aggregation) + treefmt-nix.
{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.treefmt-nix.flakeModule
  ];
}
