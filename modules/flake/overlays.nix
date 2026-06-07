# nixpkgs overlays (`#overlays.*`), imported from ./../../overlays.
{ inputs, ... }:
{
  flake.overlays = import (inputs.self + "/overlays") {
    inherit inputs;
    inherit (inputs) self;
  };
}
