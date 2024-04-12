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

    hardware.url = "github:nixos/nixos-hardware";
    impermanence.url = "github:nix-community/impermanence";
    nix-colors.url = "github:misterio77/nix-colors";

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
  # TODO: make this simpler like misterio77's
  outputs =
    { home-manager
    , nixpkgs
    , self
    , ...
    }@inputs:
    let
      inherit (self) outputs;
      # Good nix configs:
      # https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0/flake.nix
      # https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af/flake.nix#L48
      # https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0/overlays/zjstatus/default.nix#L2
      overlays = [
        inputs.alacritty-theme.overlays.default
        inputs.nur.overlay
        (self: super: {
          ctpv = inputs.ctpv.packages.${self.system}.default;
          # idk if I should be using cuda version here or not
          ollama = inputs.ollama.packages.${self.system}.default;
          mpv = super.mpv.override {
            scripts = with self.mpvScripts; [
              autoload # autoloads entries before and after current entry
              mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
              quality-menu # control video quality on the fly
              webtorrent-mpv-hook # extends mpv to handle magnet URLs
            ] ++
            # extends mpv to be controllable with MPD
            self.lib.optional (self.system == "x86_64-linux") self.mpvScripts.mpris
            ;
          };
          # TODO: do I need this?
          # use full ffmpeg version to support all video formats
          # mpv-unwrapped = super.mpv-unwrapped.override {
          # ffmpeg_5 = ffmpeg_5-full;
          # };
          weechat = super.weechat.override {
            configure = { availablePlugins, ... }: {
              scripts = with super.weechatScripts; [
                # Idk how to use this one yet
                edit # edit messages in $EDITOR
                wee-slack # slack in weechat
                # I think weeslack already has way to facilitate notifications
                # weechat-notify-send # highlight and notify bindings to notify-send
                weechat-go # command pallette jumping
              ];
            };
          };
        })
      ];
      nixModule = ({ config, pkgs, ... }: {
        nixpkgs.overlays = overlays;
        nix.registry = {
          # This setting is important because it makes things like:
          # `nix run nixpkgs#some-package` makes it use the same reference of packages as in your 
          # flake.lock, which helps prevent the package from being different every time you run it
          home-manager.flake = self.inputs.home-manager;
          nixpkgs.flake = self.inputs.nixpkgs;
          nur.flake = self.inputs.nur;
        };
        nixpkgs.config = {
          allowUnfree = true;
          packageOverrides = pkgs: {
            nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
              inherit pkgs;
            };
          };
        };
      });


      systems = [ "x86_64-linux" "aarch64-darwin" ];
      lib = nixpkgs.lib // home-manager.lib;
      pkgsFor = lib.genAttrs systems (system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      });
      forEachSystem = f: lib.genAttrs systems (system: f pkgsFor.${system});
    in
    {
      inherit lib;
      # TODO: make the import of this global like misterio
      overlays = import ./overlays { inherit inputs outputs; };
      packages = forEachSystem (pkgs: import ./pkgs { inherit pkgs; });

      nixosConfigurations = {
        praesidium = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./hosts/praesidium
            nixModule
            ./modules/linux
            inputs.nur.nixosModules.nur
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit inputs outputs; };
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

      darwinConfigurations = let system = "aarch64-darwin"; in
        {
          Xaviers-MacBook-Air = inputs.darwin.lib.darwinSystem {
            inherit system;
            pkgs = import inputs.nixpkgs { inherit system overlays; };
            specialArgs = { };
            modules = [
              nixModule
              ./modules/darwin
              home-manager.darwinModules.home-manager
              {
                home-manager = {
                  extraSpecialArgs = { inherit inputs outputs; };
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
