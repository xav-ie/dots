# `configurations.{nixos,darwin}.<name>.module` → `#{nixos,darwin}Configurations.*`.
{
  lib,
  config,
  inputs,
  ...
}:
let
  configModuleType = lib.types.lazyAttrsOf (
    lib.types.submodule {
      options.module = lib.mkOption {
        type = lib.types.deferredModule;
      };
    }
  );
in
{
  options.configurations = {
    nixos = lib.mkOption {
      type = configModuleType;
      default = { };
      description = "NixOS configurations, keyed by hostname.";
    };
    darwin = lib.mkOption {
      type = configModuleType;
      default = { };
      description = "nix-darwin configurations, keyed by hostname.";
    };
  };

  config.flake = {
    nixosConfigurations = lib.mapAttrs (
      _name:
      { module }:
      inputs.nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ module ];
      }
    ) config.configurations.nixos;

    darwinConfigurations = lib.mapAttrs (
      _name:
      { module }:
      inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [ module ];
      }
    ) config.configurations.darwin;
  };
}
