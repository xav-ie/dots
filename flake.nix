{
  description = "My NixOS";
  nixConfig = {
    extra-trusted-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  inputs = {
    hardware.url = "github:nixos/nixos-hardware";
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

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
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    generate-kaomoji = {
      url = "github:xav-ie/generate-kaomoji";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # the latest and greatest ollama
    ollama.url = "github:abysssol/ollama-flake";
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-23.11";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zjstatus = {
      url = "github:dj95/zjstatus";
    };
    alacritty-theme = {
      url = "github:alexghr/alacritty-theme.nix";
    };
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
      # Good nix configs:
      # https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/flake.nix
      # https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af/flake.nix#L48
      # https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0/overlays/zjstatus/default.nix#L2

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
      inherit lib;
      # TODO: make the import of this global like misterio
      overlays = import ./overlays { inherit inputs outputs; };
      # right now, these only get pure nixpkgs...
      # idk if it is good idea to pass in pkgs and overlays.. arghghghgh
      packages = forEachSystem (pkgs: import ./pkgs { inherit pkgs; });
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
                users.x.imports = [
                  ./modules/home-manager/default.nix
                  ./modules/home-manager/linux.nix
                ];
              };
            }
          ];
        };
      };

      darwinConfigurations = {
        # macbook air
        castra = inputs.darwin.lib.darwinSystem {
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
                users.xavierruiz.imports = [
                  ./modules/home-manager/default.nix
                  ./modules/home-manager/darwin.nix
                ];
              };
            }
          ];
        };
      };
    };
}
