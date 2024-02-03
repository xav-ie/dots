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
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
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
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
    , wezterm
    , zjstatus
    , ...
    } @ inputs:
    let
      # Good nix configs:
      # https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af/flake.nix#L48
      # https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0/overlays/zjstatus/default.nix#L2
      overlays = [
        nur.overlay
        (self: super: {
          ctpv = inputs.ctpv.packages.${self.system}.default;
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
        nixpkgs.overlays = [ overlays ];
        # This setting is important because it makes things like:
        # `nix run nixpkgs#some-package` makes it use the same reference of packages as in your 
        # flake.lock, which helps prevent the package from being different every time you run it
        nix.registry.nixpkgs.flake = self.inputs.nixpkgs;
        nixpkgs.config = {
          allowUnfree = true;
        };
      });
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs nur wezterm zjstatus; };
          modules = [
            nixModule
            ./nixos/configuration.nix
            nur.nixosModules.nur
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit inputs nur wezterm zjstatus hyprland-contrib; };
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
          Xaviers-MacBook-Air = darwin.lib.darwinSystem {
            inherit system;
            pkgs = import inputs.nixpkgs { inherit system overlays; };
            specialArgs = { };
            modules = [
              nixModule
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
              }
            ];
          };
        };
    };
}
