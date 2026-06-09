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

  config.flake =
    let
      # Only expose configurations whose target system is in the active
      # `systems` set. `just check` overrides `systems` to the current platform
      # (e.g. aarch64-darwin) so `nix flake check` validates only the current
      # host; without this filter it would still instantiate the cross-platform
      # hosts (e.g. praesidium on x86_64-linux), whose overlay pulls
      # `self.packages.<system>` for a system flake-parts no longer generates.
      # `nixpkgs.hostPlatform` is read directly, so this never forces the
      # overlay/package set.
      forActiveSystems = lib.filterAttrs (
        _name: cfg: lib.elem cfg.config.nixpkgs.hostPlatform.system config.systems
      );
    in
    {
      nixosConfigurations = forActiveSystems (
        lib.mapAttrs (
          _name:
          { module }:
          inputs.nixpkgs.lib.nixosSystem {
            specialArgs = { inherit inputs; };
            modules = [ module ];
          }
        ) config.configurations.nixos
      );

      darwinConfigurations = forActiveSystems (
        lib.mapAttrs (
          _name:
          { module }:
          inputs.nix-darwin.lib.darwinSystem {
            specialArgs = { inherit inputs; };
            modules = [ module ];
          }
        ) config.configurations.darwin
      );
    };
}
