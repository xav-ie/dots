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
  };
  outputs = {
    darwin,
    nixpkgs,
    home-manager,
    nur,
    zjstatus,
    ...
  } @ inputs: let
    nix.registry.nixpkgs.flake = nixpkgs;
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
    overlays = with inputs; [
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
              users.x = import ./home-manager/home.nix;
              # extraSpecialArgs = { inherit inputs; };
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
          ({pkgs, ...}: {
            # darwin prefs and config items
            programs.zsh.enable = true;
            environment.shells = [pkgs.bash pkgs.zsh];
            environment.loginShell = pkgs.zsh;
            nix.extraOptions = ''
              experimental-features = nix-command flakes
            '';
            fonts.fontDir.enable = true;
            fonts.fonts = [(pkgs.nerdfonts.override {fonts = ["Meslo"];})];
            services.nix-daemon.enable = true;
            # BECAUSE YA HAVE TO :/
            # https://github.com/nix-community/home-manager/issues/4026
            users.users.xavierruiz.home = "/Users/xavierruiz";
            system = {
              #packages = [pkgs.coreutils];
              keyboard.enableKeyMapping = true;
              keyboard.remapCapsLockToEscape = true;
              defaults = {
                finder = {
                  AppleShowAllExtensions = true;
                  _FXShowPosixPathInTitle = true;
                };
                dock = {
                  autohide = true;
                };
              };
            };
          })
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.xavierruiz.imports = [
                ({pkgs, ...}: {
                  home.packages = [pkgs.ripgrep pkgs.fd pkgs.curl pkgs.eza];
                  # The state version is required and should stay at the version you
                  # originally installed.
                  home.stateVersion = "23.11";
                  home.sessionVariables = {
                    PAGER = "bat";
                    EDITOR = "nvim";
                  };
                  programs = {
                    bat = {
                      enable = true;
                      config.theme = "TwoDark";
                    };
                    fzf = {
                      enable = true;
                      enableZshIntegration = true;
                    };
                    git = {enable = true;};
                    zsh = {
                      enable = true;
                      enableCompletion = true;
                      enableAutosuggestions = true;
                      enableSyntaxHighlighting = true;
                      shellAliases = {
                        ls = "exa";
                      };
                    };
                    starship = {
                      enable = true;
                      enableZshIntegration = true;
                    };
                    alacritty = {
                      enable = true;
                      settings.font.normal.family = "MesloLGS Nerd Font Mono";
                      settings.fontSize = 16;
                    };
                  };
                })
              ];
              # users.x = import ./home-manager/home.nix;
            };
            nixpkgs.overlays = [nur.overlay];
          }
        ];
      };
    };
  };
}
