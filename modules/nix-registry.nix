# Pin every flake input into the nix registry + legacy nixPath, so `nix run
# nixpkgs#…` and `<nixpkgs>` resolve to this flake's inputs. Handy interactively,
# but it drags every input source tree (~2 GB+) into the closure — so it lives on
# the interactive sets (`linux`, `darwin.macos`), not the lean server `base`.
{ ... }:
let
  registryModule =
    {
      config,
      inputs,
      lib,
      ...
    }:
    {
      nix.registry =
        inputs |> lib.filterAttrs (name: _: name != "self") |> lib.mapAttrs (_: value: { flake = value; });
      nix.nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
    };
in
{
  flake.modules.nixos.linux = registryModule;
  flake.modules.darwin.macos = registryModule;
}
