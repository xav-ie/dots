# nox — MacBook Air M3 (aarch64-darwin).
{ config, inputs, ... }:
let
  flakeModules = config.flake.modules;
in
{
  configurations.darwin.nox.module =
    { config, ... }:
    {
      imports = [
        flakeModules.darwin.common
        flakeModules.darwin.macos
        inputs.home-manager.darwinModules.home-manager
        ./_nox-body.nix
      ];

      nixpkgs.hostPlatform = "aarch64-darwin";

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        users.${config.defaultUser} = {
          imports = [
            flakeModules.homeManager.common
            flakeModules.homeManager.darwin
          ];
          # Pin to the home-manager release this host was first set up on.
          home.stateVersion = "23.11";
        };
      };
    };
}
