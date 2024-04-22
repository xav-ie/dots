{ pkgs, inputs, ... }:
{
  nix = {
    # https://nixos.wiki/wiki/Storage_optimization
    gc = {
      automatic = true;
      persistent = true;
      dates = "weekly";
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
      j
      jira-task-list
      jira-list
      notify
      nvim
      searcher
      uair-toggle-and-notify
      zellij-tab-name-update
    ]
  );
}
