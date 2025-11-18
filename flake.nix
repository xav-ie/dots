{
  description = "Xavier's NixOS";
  inputs = {
    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
    ctpv.url = "github:xav-ie/ctpv-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    generate-kaomoji.url = "github:xav-ie/generate-kaomoji";
    hardware.url = "github:nixos/nixos-hardware";
    home-manager.url = "github:nix-community/home-manager";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    jj.url = "github:martinvonz/jj";
    morlana.url = "github:ryanccn/morlana";
    nix-auto-follow.url = "github:xav-ie/nix-auto-follow/feat-consolidation";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-homeassistant.url = "github:nixos/nixpkgs/master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/NUR";
    nuenv.url = "github:xav-ie/nuenv";
    plover-flake.url = "github:openstenoproject/plover-flake";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    sops-nix.url = "github:Mic92/sops-nix";
    virtual-headset.url = "github:xav-ie/virtual-headset";
    systems.url = "github:nix-systems/default";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    waybar.url = "github:Alexays/waybar";
    zjstatus.url = "github:dj95/zjstatus";
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

    # transitive deps that are used by multiple inputs
    crane.url = "github:ipetkov/crane";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-utils.url = "github:numtide/flake-utils";
    gitignore.url = "github:hercules-ci/gitignore.nix";
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    rust-overlay.url = "github:oxalica/rust-overlay";

    # overrides
    alacritty-theme-themes.flake = false;
    alacritty-theme-themes.url = "github:alacritty/alacritty-theme";
    alacritty-theme.inputs.alacritty-theme.follows = "alacritty-theme-themes";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib-v1-merge";
    # before v2 merge check
    nixpkgs-lib-v1-merge.url = "github:nix-community/nixpkgs.lib/a73b9c743612e4244d865a2fdee11865283c04e6";

    # vendored
    homebrew-bundle.flake = false;
    homebrew-bundle.url = "github:homebrew/homebrew-bundle";
    homebrew-cask.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-core.flake = false;
    homebrew-core.url = "github:homebrew/homebrew-core";
    obs-backgroundremoval.flake = false;
    obs-backgroundremoval.url = "github:royshil/obs-backgroundremoval";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (toplevel: {
      debug = true;

      systems = import inputs.systems;

      imports = [
        # inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          config,
          lib,
          pkgs,
          system,
          ...
        }:
        {
          # uncomment if you need overlays at the top level for some reason...
          # _module.args.pkgs = import inputs.nixpkgs {
          #   inherit system;
          #   overlays = builtins.attrValues self.overlays;
          # };

          devShells.default = pkgs.mkShell {
            packages =
              (with pkgs; [
                just
                nix-diff
                nushell
              ])
              ++ lib.optionals pkgs.stdenv.isLinux (
                with pkgs;
                [
                  nh
                  nixos-rebuild
                ]
              )
              ++ lib.optionals pkgs.stdenv.isDarwin [
                inputs.morlana.packages.${system}.default
                inputs.nix-darwin.packages.${system}.default
              ]
              ++ [ config.treefmt.build.wrapper ]
              ++ [ inputs.nix-auto-follow.packages.${system}.default ];

            shellHook = ''
              printf "\n🐢 Use \e[32;40mjust\e[0m to build the system."
              printf "\n💄 Use \e[32;40mtreefmt\e[0m to format the files."
            '';
          };

          packages = import ./packages {
            generate-kaomoji = inputs.generate-kaomoji.packages.${system}.default;
            pkgs = import inputs.nixpkgs-bleeding {
              inherit system;
              config.allowUnfree = true;
            };
            nuenv = inputs.nuenv.lib;
          };

          treefmt =
            { options, ... }:
            {
              programs = {
                # buggy so far...
                # nufmt.enable = true;
                clang-format = {
                  enable = true;
                  includes = options.programs.clang-format.includes.default ++ [ "*.glsl" ];
                };
                deadnix.enable = true;
                just.enable = true;
                kdlfmt.enable = true;
                nixfmt.enable = true;
                prettier = {
                  enable = true;
                  package = config.packages.prettier-with-toml;
                  includes = options.programs.prettier.includes.default ++ [ "*.toml" ];
                };
                ruff.enable = true;
                shfmt.enable = true;
                statix.enable = true;
                swift-format.enable = true;
              };
              settings = {
                on-unmatched = "fatal";
                excludes = [
                  "*.conf"
                  "*.patch"
                  ".git-blame-ignore-revs"
                  ".gitignore"
                  "flake.lock"
                  # formatter is borked
                  "*.nu"
                  # sops has its own formatter
                  "secrets/*.yaml"
                ];
              };
            };

        };

      flake = {
        overlays = import ./overlays toplevel;
        darwinConfigurations = import ./darwinConfigurations toplevel;
        nixosConfigurations = import ./nixosConfigurations toplevel;
      };
    });
}
