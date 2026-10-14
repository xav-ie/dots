# Pin a few flake inputs into the nix registry + legacy nixPath, so `nix run
# nixpkgs#…` and `<nixpkgs>` resolve to this flake's inputs. Keep this list
# SMALL: every entry drags its source tree into the system closure (~1 GB for
# the full input set). Hence interactive sets (`linux`, `darwin.macos`) only.
_:
let
  # Only inputs actually used as flake-refs interactively.
  pinned = [
    "nixpkgs"
    "nixpkgs-bleeding"
  ];
in
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
        inputs
        |> lib.filterAttrs (name: _: builtins.elem name pinned)
        |> lib.mapAttrs (_: value: { flake = value; });
      nix.nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
    };
in
{
  flake.modules.nixos.linux = registryModule;
  flake.modules.darwin.macos = registryModule;
}
