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
    home-manager,
    hyprland-contrib,
    nixpkgs,
    nur,
    pwnvim,
    self,
    zjstatus,
    ...
  } @ inputs: let
    nix.registry.nixpkgs.flake = nixpkgs;
    # TODO: move to overlays because they are supposed to be better but I can't seem to figure them out :(
    # Some other ppl who got them working:
    # https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af/flake.nix#L48
    # https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0/overlays/zjstatus/default.nix#L2
    #
    # system = "x86_64-linux";
    # system = "aarch64-darwin";
    # no idea what this does
    # pkgs = import nixpkgs {
    #   inherit system;
    # };
  in {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs nur zjstatus;};
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
              extraSpecialArgs = {inherit inputs nur zjstatus hyprland-contrib;};
            };
          }
        ];
      };
    };
    darwinConfigurations = {
      Xaviers-MacBook-Air = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        pkgs = import inputs.nixpkgs {system = "aarch64-darwin";};
        specialArgs = {inherit inputs nur zjstatus;};
        modules = [
          ./modules/darwin
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              extraSpecialArgs = {inherit pwnvim inputs nur zjstatus;};
              useGlobalPkgs = true;
              useUserPackages = true;
              users.xavierruiz.imports = [
                ./modules/home-manager/default.nix
                ./modules/home-manager/darwin.nix
              ];
            };
            nixpkgs.overlays = [nur.overlay];
          }
        ];
      };
    };
  };
}
