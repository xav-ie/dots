{
  description = "My NixOS";
  nixConfig = {
    extra-trusted-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-bleeding = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    zjstatus = {
      url = "github:dj95/zjstatus";
    };
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pwnvim = {
      url = "github:zmre/pwnvim";
    };
  };
  outputs = {
    darwin,
    nixpkgs,
    home-manager,
    pwnvim,
    nur,
    zjstatus,
    ...
  } @ inputs: let
    nix.registry.nixpkgs.flake = nixpkgs;
    # system = "x86_64-linux";
    # system = "aarch64-darwin";
    # no idea what this does
    # pkgs = import nixpkgs {
    #   inherit system;
    # };
    zjstatusOverlay = with inputs; [
      (final: prev: {
        zjstatus = zjstatus.packages.${prev.system}.default;
      })
    ];
  in {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs nur;};
        modules = [
          ./nixos/configuration.nix
          nur.nixosModules.nur
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [nur.overlay];
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.x.imports = [
                ./modules/home-manager/default.nix
                ./modules/home-manager/linux.nix
              ];
              # extraSpecialArgs = {inherit inputs;};
            };
          }
        ];
      };
    };
    darwinConfigurations = {
      Xaviers-MacBook-Air = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        pkgs = import inputs.nixpkgs {system = "aarch64-darwin";};
        modules = [
          ./modules/darwin
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              extraSpecialArgs = {inherit pwnvim;};
              useGlobalPkgs = true;
              useUserPackages = true;
              users.xavierruiz.imports = [
                ./modules/home-manager/default.nix
                ./modules/home-manager/darwin.nix
              ];
            };
            nixpkgs.overlays = [nur.overlay zjstatusOverlay];
          }
        ];
      };
    };
  };
}
