{
  description = "My NixOS";
  nixConfig = {
    # I am still not exactly sure what the point of these are...
    # they do not affect nix.conf
    # read more at:
    # https://github.com/NixOS/nix/issues/6672
    # https://github.com/NixOS/nix/issues/5988
    # There also seems to be some difference using "extra"
    # https://github.com/NixOS/nix/issues/6672#issuecomment-1921937241
    extra-trusted-substituters = [
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
  };
  inputs = {
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

    alacritty-theme = {
      url = "github:alexghr/alacritty-theme.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hardware = {
      url = "github:nixos/nixos-hardware";
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
      url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
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
    ollama = {
      url = "github:abysssol/ollama-flake";
    };
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-23.11";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    waybar = {
      url = "github:Alexays/waybar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zjstatus = {
      url = "github:dj95/zjstatus";
      inputs.nixpkgs.follows = "nixpkgs";
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
                users.x.imports = [
                  ./modules/home-manager
                  ./modules/home-manager/linux
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
