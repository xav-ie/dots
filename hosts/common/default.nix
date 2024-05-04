{ pkgs, inputs, ... }:
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
    registry = {
      # This setting is important because it makes things like:
      # `nix run nixpkgs#some-package` makes it use the same reference of packages as in your 
      # flake.lock, which helps prevent the package from being different every time you run it
      home-manager.flake = inputs.home-manager;
      nixpkgs.flake = inputs.nixpkgs;
      nur.flake = inputs.nur;
    };
    settings = {
      # just run this every once in a while... auto-optimization slows down evaluation
      auto-optimise-store = false;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
      extra-trusted-substituters = [
        "https://nix-community.cachix.org"
        "https://devenv.cachix.or"
      ];
      fallback = true; # allow building from src
      # use max cores/threads when `enableParallelBuilding` is set for package
      cores = 0;
      # use max CPUs for nix build jobs
      max-jobs = "auto";
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  environment.systemPackages = (
    with pkgs;
    [
      # TODO: put these in a better place
      cache-command
      ff
      generate-kaomoji
      is-sshed
      j
      jira-list
      jira-task-list
      notify
      nvim
      searcher
      uair-toggle-and-notify
      zellij-tab-name-update
    ]
  );
}
