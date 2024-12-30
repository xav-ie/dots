{
  description = "Xavier's NixOS";
  inputs = {
    ctpv.inputs.flake-utils.follows = "flake-utils";
    ctpv.inputs.nixpkgs.follows = "nixpkgs";
    ctpv.url = "github:xav-ie/ctpv-nix";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.inputs.systems.follows = "systems";
    flake-utils.url = "github:numtide/flake-utils";
    generate-kaomoji.inputs.flake-utils.follows = "flake-utils";
    generate-kaomoji.inputs.nixpkgs.follows = "nixpkgs";
    generate-kaomoji.url = "github:xav-ie/generate-kaomoji";
    ghostty.inputs.flake-compat.follows = "flake-compat";
    ghostty.inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    ghostty.inputs.zig.follows = "zig";
    ghostty.url = "git+ssh://git@github.com/ghostty-org/ghostty";
    hardware.url = "github:nixos/nixos-hardware";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    hyprland-contrib.inputs.nixpkgs.follows = "nixpkgs";
    hyprland-contrib.url = "github:hyprwm/contrib";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.inputs.pre-commit-hooks.follows = "pre-commit-hooks";
    hyprland.inputs.systems.follows = "systems-linux";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-homebrew.inputs.flake-utils.follows = "flake-utils";
    nix-homebrew.inputs.nix-darwin.follows = "nix-darwin";
    nix-homebrew.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs/master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nur.inputs.flake-parts.follows = "flake-parts";
    nur.inputs.nixpkgs.follows = "nixpkgs";
    nur.inputs.treefmt-nix.follows = "treefmt-nix";
    nur.url = "github:nix-community/NUR";
    pre-commit-hooks.inputs.flake-compat.follows = "flake-compat";
    pre-commit-hooks.inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    systems-linux.url = "github:nix-systems/default-linux";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    waybar.inputs.flake-compat.follows = "flake-compat";
    waybar.inputs.nixpkgs.follows = "nixpkgs";
    waybar.url = "github:Alexays/waybar";
    zig.inputs.flake-compat.follows = "flake-compat";
    zig.inputs.flake-utils.follows = "flake-utils";
    zig.inputs.nixpkgs.follows = "nixpkgs";
    zig.url = "github:mitchellh/zig-overlay";
    # zj has exact inputs
    # zjstatus.inputs.flake-utils.follows = "flake-utils";
    # zjstatus.inputs.nixpkgs.follows = "nixpkgs";
    # zjstatus.inputs.rust-overlay.follows = "rust-overlay";
    zjstatus.url = "github:dj95/zjstatus";

    # alacritty-theme.inputs.flake-parts.follows = "flake-parts";
    # alacritty-theme.inputs.nixpkgs.follows = "nixpkgs";
    # alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
    # wezterm.inputs.flake-utils.follows = "flake-utils";
    # wezterm.inputs.nixpkgs.follows = "nixpkgs";
    # wezterm.url = "github:wez/wezterm?dir=nix";
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

    # vendored
    homebrew-bundle.flake = false;
    homebrew-bundle.url = "github:homebrew/homebrew-bundle";
    homebrew-cask.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-core.flake = false;
    homebrew-core.url = "github:homebrew/homebrew-core";
  };
  outputs =
    {
      home-manager,
      nixpkgs,
      self,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      user = "x";
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      lib = nixpkgs.lib // home-manager.lib;
      pkgsFor = lib.genAttrs systems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
      forEachSystem = f: lib.genAttrs systems (system: f pkgsFor.${system});
    in
    {
      # TODO: make the import of this global like misterio
      overlays = import ./overlays { inherit inputs outputs; };
      packages = forEachSystem (pkgs: import ./pkgs { inherit pkgs; });
      formatter = forEachSystem (pkgs: pkgs.nixfmt-rfc-style);
      # Reusable nixos modules you might want to export
      # TODO: refactor these into proper, shareable modules
      # These are usually stuff you would upstream into nixpkgs
      # nixosModules = import ./modules/nixos;
      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # homeManagerModules = import ./modules/home-manager;

      nixosConfigurations = {
        # custom desktop tower
        praesidium = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
          };
          modules = [
            ./hosts/praesidium
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs outputs;
                };
                useGlobalPkgs = true;
                useUserPackages = true;
                users."${user}".imports = [
                  ./modules/home-manager
                  ./modules/home-manager/linux
                ];
              };
            }
          ];
        };
      };

      darwinConfigurations = {
        # macbook air - m1
        castra = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            inherit inputs outputs;
          };
          modules = [
            ./hosts/castra
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs outputs;
                };
                useGlobalPkgs = true;
                useUserPackages = true;
                users."${user}".imports = [
                  ./modules/home-manager
                  ./modules/home-manager/darwin
                ];
              };
            }
          ];
        };

        # macbook air - m3
        stella = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            inherit inputs outputs;
          };
          modules = [
            ./hosts/stella
            # TODO: clean this up
            inputs.nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                # Install Homebrew under the default prefix
                enable = true;
                # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
                enableRosetta = true;
                # User owning the Homebrew prefix
                inherit user;
                # Optional: Declarative tap management
                taps = {
                  "homebrew/homebrew-core" = inputs.homebrew-core;
                  "homebrew/homebrew-cask" = inputs.homebrew-cask;
                  "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
                };
                # Optional: Enable fully-declarative tap management
                # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
                mutableTaps = false;
              };
            }
            (
              { config, ... }:
              {
                # https://github.com/zhaofengli/nix-homebrew/issues/5
                # You must tell nix-darwin to just inherit the same taps as nix-homebrew
                homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
              }
            )

            home-manager.darwinModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs outputs;
                };
                useGlobalPkgs = true;
                useUserPackages = true;
                users."${user}".imports = [
                  ./modules/home-manager
                  ./modules/home-manager/darwin
                ];
              };
            }
          ];
        };
      };
    };
}
