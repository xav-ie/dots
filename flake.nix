{
  description = "My NixOS";
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
  };
  outputs = { nixpkgs, home-manager, nur, ... }@inputs:
  let 
    nix.registry.nixpkgs.flake = nixpkgs;
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      }; 
    };
  in 
  {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
       specialArgs = { inherit inputs nur; }; 
       modules = [
         ./nixos/configuration.nix
         nur.nixosModules.nur
         home-manager.nixosModules.home-manager {
           home-manager.useGlobalPkgs = true;
           home-manager.useUserPackages = true;
           home-manager.users.x = import ./home-manager/home.nix;
           nixpkgs.overlays = [ inputs.nur.overlay ];
           # home-manager.extraSpecialArgs = { inherit inputs; };
         }
       ];
      };
    }; 
  };
}
