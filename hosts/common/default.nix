{
  config,
  lib,
  inputs,
  ...
}:
{
  nix = {
    # https://nixos.wiki/wiki/Storage_optimization
    gc = {
      automatic = true;
      # these two options do not have an effect on macos... >:(
      # persistent = true; 
      # dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # just run this every once in a while... auto-optimization slows down evaluation
      auto-optimise-store = false;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      extra-trusted-substituters = [
        "https://devenv.cachix.org"
        "https://nix-community.cachix.org"
      ];
      fallback = true; # allow building from src
      # use max cores/threads when `enableParallelBuilding` is set for package
      cores = 0;
      # use max CPUs for nix build jobs
      max-jobs = "auto";
      sandbox = true;
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
  };
}
