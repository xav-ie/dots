/*
  @module common - Common configuration for all darwinConfigurations and
  nixosConfigurations
*/
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./user.nix ];

  config = {
    # Ensure per-user gcroots directory exists for GC root pinning
    system.activationScripts.postActivation.text = # sh
      ''
        install -d -o ${config.defaultUser} -m 0755 /nix/var/nix/gcroots/per-user/${config.defaultUser}
      '';

    nix = {
      enable = true;
      # https://nixos.wiki/wiki/Storage_optimization
      gc = {
        automatic = pkgs.stdenv.isDarwin;
        # these two options do not have an effect on macos... >:(
        # persistent = true;
        # dates = "weekly";
        options = "--delete-older-than 30d";
      };

      # This will add each flake input as a registry
      # To make nix3 commands consistent with your flake
      registry = lib.mapAttrs (_: value: { flake = value; }) (
        # very important, would otherwise cause full eval of git repo after
        # *any* change
        lib.filterAttrs (name: _: name != "self") inputs
      );

      # This will additionally add your inputs to the system's legacy channels
      # Making legacy nix commands consistent as well, awesome!
      nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

      settings = {
        # just run this every once in a while... auto-optimization slows down evaluation
        auto-optimise-store = false;
        # allow remote builders to use local substituters
        builders-use-substitutes = true;
        # TODO: do I need this?
        # builders = lib.mkForce "ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 4 - - - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        extra-trusted-substituters = [
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
        ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
        trusted-users = [ config.defaultUser ];
        fallback = true; # allow building from src
        # use max cores/threads when `enableParallelBuilding` is set for package
        cores = 0;
        # use max CPUs for nix build jobs
        max-jobs = "auto";
        sandbox = "relaxed";
      };
    };

    nixpkgs = {
      # config.allowBroken = true;
      # config.allowUnsupportedSystem = true;
      # config.allowUnfree = true;
      overlays = builtins.attrValues inputs.self.overlays;
    };
  };
}
