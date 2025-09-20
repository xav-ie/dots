{
  description = "Xavier's NixOS";
  inputs = {
    alacritty-theme.inputs.flake-parts.follows = "flake-parts";
    alacritty-theme.inputs.nixpkgs.follows = "nixpkgs";
    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
    ctpv.inputs.flake-utils.follows = "flake-utils";
    ctpv.inputs.nixpkgs.follows = "nixpkgs";
    ctpv.url = "github:xav-ie/ctpv-nix";
    devenv.url = "github:cachix/devenv";
    devenv-root.flake = false;
    devenv-root.url = "file+file:///dev/null";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.inputs.systems.follows = "systems";
    flake-utils.url = "github:numtide/flake-utils";
    generate-kaomoji.inputs.flake-utils.follows = "flake-utils";
    generate-kaomoji.inputs.nixpkgs.follows = "nixpkgs";
    generate-kaomoji.url = "github:xav-ie/generate-kaomoji";
    # ghostty.inputs.flake-compat.follows = "flake-compat";
    # ghostty.inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    # ghostty.inputs.zig.follows = "zig";
    # ghostty.url = "git+ssh://git@github.com/ghostty-org/ghostty";
    hardware.url = "github:nixos/nixos-hardware";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    # because firefox has strange rendering bug
    firefox-nixpkgs.url = "github:nixos/nixpkgs/88195a94f390381c6afcdaa933c2f6ff93959cb4";
    hyprland-contrib.inputs.nixpkgs.follows = "nixpkgs";
    hyprland-contrib.url = "github:hyprwm/contrib";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.inputs.pre-commit-hooks.follows = "pre-commit-hooks";
    hyprland.inputs.systems.follows = "systems-linux";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    jj.url = "github:martinvonz/jj";
    jj.inputs."flake-utils".follows = "flake-utils";
    jj.inputs."nixpkgs".follows = "nixpkgs-bleeding";
    jj.inputs.rust-overlay.follows = "rust-overlay";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    morlana.url = "github:ryanccn/morlana";
    morlana.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs/master";
    nixpkgs-homeassistant.url = "github:nixos/nixpkgs/master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    notification-cleaner.url = "github:xav-ie/notification-cleaner";
    notification-cleaner.inputs.devenv.follows = "devenv";
    notification-cleaner.inputs.devenv-root.follows = "devenv-root";
    notification-cleaner.inputs.flake-parts.follows = "flake-parts";
    notification-cleaner.inputs.mk-shell-bin.follows = "mk-shell-bin";
    notification-cleaner.inputs.nixpkgs.follows = "nixpkgs";
    notification-cleaner.inputs.nix2container.follows = "nix2container";
    nur.inputs.flake-parts.follows = "flake-parts";
    nur.inputs.nixpkgs.follows = "nixpkgs";
    nur.inputs.treefmt-nix.follows = "treefmt-nix";
    nur.url = "github:nix-community/NUR";
    nuenv.url = "github:xav-ie/nuenv";
    nuenv.inputs.nixpkgs.follows = "nixpkgs";
    nuenv.inputs.systems.follows = "systems";
    pre-commit-hooks.inputs.flake-compat.follows = "flake-compat";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    systems-linux.url = "github:nix-systems/default-linux";
    systems.url = "github:nix-systems/default";
    # kind of breaks `nix flake check` but idk for sure
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    waybar.inputs.flake-compat.follows = "flake-compat";
    waybar.inputs.nixpkgs.follows = "nixpkgs";
    waybar.url = "github:Alexays/waybar";
    # zig.inputs.flake-compat.follows = "flake-compat";
    # zig.inputs.flake-utils.follows = "flake-utils";
    # zig.inputs.nixpkgs.follows = "nixpkgs";
    # zig.url = "github:mitchellh/zig-overlay";
    # zj has exact inputs
    # zjstatus.inputs.flake-utils.follows = "flake-utils";
    # zjstatus.inputs.nixpkgs.follows = "nixpkgs";
    # zjstatus.inputs.rust-overlay.follows = "rust-overlay";
    zjstatus.url = "github:dj95/zjstatus";

    # wezterm.inputs.flake-utils.follows = "flake-utils";
    # wezterm.inputs.nixpkgs.follows = "nixpkgs";
    # wezterm.url = "github:wez/wezterm?dir=nix";
    # TODO: figure out how to use from misterio and vimjoyer
    # impermanence.url = "github:nix-community/impermanence";
    # nix-colors.url = "github:misterio77/nix-colors";

    # vendored
    homebrew-bundle.flake = false;
    homebrew-bundle.url = "github:homebrew/homebrew-bundle";
    homebrew-cask.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-core.flake = false;
    homebrew-core.url = "github:homebrew/homebrew-core";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (toplevel: {
      debug = true;

      systems = import inputs.systems;

      imports = [
        inputs.devenv.flakeModule
        # inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
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

          devenv.shells.default = {
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
              ];

            enterShell = ''
              printf "🐢 Use \e[32;40mjust\e[0m to build the system.\n"
            '';
          };

          packages = import ./packages {
            generate-kaomoji = inputs.generate-kaomoji.packages.${system}.default;
            pkgs = inputs.nixpkgs-bleeding.legacyPackages.${system};
            nuenv = inputs.nuenv.lib;
          };

          treefmt = {
            programs = {
              # buggy so far...
              # nufmt.enable = true;
              clang-format.enable = true;
              clang-format.includes = [ "*.glsl" ];
              deadnix.enable = true;
              just.enable = true;
              kdlfmt.enable = true;
              nixfmt.enable = true;
              prettier.enable = true;
              ruff.enable = true;
              shfmt.enable = true;
              statix.enable = true;
              swift-format.enable = true;
              taplo.enable = true;
            };
            settings.global.excludes = [
              # formatter is borked
              "*.nu"
              ".git-blame-ignore-revs"
              # sops has its own formatter
              "secrets/*.yaml"
            ];
            # `prettier` does not come with a node version on purpose, so we
            # must make a wrapper
            settings.formatter.prettier.command = pkgs.writeShellScriptBin "prettier-wrapped" ''
              exec ${lib.getExe pkgs.nodejs-slim} ${lib.getExe pkgs.nodePackages.prettier} "$@"
            '';
          };

        };

      flake = {
        overlays = import ./overlays toplevel;
        darwinConfigurations = import ./darwinConfigurations toplevel;
        nixosConfigurations = import ./nixosConfigurations toplevel;
      };
    });
}
