# Injects the shared font helper (./_lib/fonts.nix) as a `fonts` module arg.
let
  fontsModule =
    { lib, pkgs, ... }:
    {
      _module.args.fonts = (import ./_lib/fonts.nix { inherit lib pkgs; }).fonts;
    };
in
{
  flake.modules.nixos.common = fontsModule;
  flake.modules.darwin.common = fontsModule;
  flake.modules.homeManager.common = fontsModule;
}
