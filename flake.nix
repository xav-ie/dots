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
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ctpv = {
      url = "github:xav-ie/ctpv-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-bleeding = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    zjstatus = {
      url = "github:dj95/zjstatus";
    };
  };
  outputs =
    { darwin
    , home-manager
    , hyprland-contrib
    , nixpkgs
    , nur
    , self
    , zjstatus
    , ...
    } @ inputs:
    let
      # TODO: what does setting this do?
      # nix.registry.nixpkgs.flake = nixpkgs;
      # TODO: move to overlays because they are supposed to be better but I can't seem to figure them out :(
      # Some other ppl who got them working:
      # https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af/flake.nix#L48
      # https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0/overlays/zjstatus/default.nix#L2
      overlays = [
        nur.overlay
        (self: super: {
          ctpv = inputs.ctpv.packages.${self.system}.default;
        })
      ];
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs nur zjstatus; };
          modules = [
            ./nixos/configuration.nix
            # I have no idea if this is working... :/
            ({ pkgs, ... }: {
              nixpkgs.overlays = overlays;
            })
            nur.nixosModules.nur
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit inputs nur zjstatus hyprland-contrib; };
                useGlobalPkgs = true;
                useUserPackages = true;
                users.x.imports = [
                  ./modules/home-manager/default.nix
                  ./modules/home-manager/linux.nix
                ];
              };
              # does this have any effect?
              nixpkgs.overlays = overlays;
            }
          ];
        };
      };
      darwinConfigurations = {
        Xaviers-MacBook-Air = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; overlays = overlays; };
          specialArgs = { inherit inputs nur zjstatus; };
          modules = [
            ./modules/darwin
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit inputs nur zjstatus; };
                useGlobalPkgs = true;
                useUserPackages = true;
                users.xavierruiz.imports = [
                  ./modules/home-manager/default.nix
                  ./modules/home-manager/darwin.nix
                ];
              };
              # does this have any effect?
              nixpkgs.overlays = overlays;
            }
          ];
        };
      };
    };
}
