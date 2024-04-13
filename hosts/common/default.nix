{ config, pkgs, inputs, ... }: {
  nix.registry = {
    # This setting is important because it makes things like:
    # `nix run nixpkgs#some-package` makes it use the same reference of packages as in your 
    # flake.lock, which helps prevent the package from being different every time you run it
    home-manager.flake = inputs.home-manager;
    nixpkgs.flake = inputs.nixpkgs;
    nur.flake = inputs.nur;
  };

  nixpkgs.config = {
    allowUnfree = true;
    packageOverrides = pkgs: {
      # TODO: this clearly is not the right way to do this
      nur = import
        (builtins.fetchTarball {
          url = "https://github.com/nix-community/NUR/archive/master.tar.gz";
          sha256 = "sha256:05s8hplcmx3p15p1qjjliqbq7g70ck3r48kgmf5wxzh60sv789b0";
        })
        {
          inherit pkgs;
        };
    };

  };

  environment.systemPackages =
    (with pkgs;
    [
      # TODO: put these in a better place
      cache-command
      ff
      j
      jira-task-list
      jira-list
      nvim
      searcher
      zellij-tab-name-update
    ]);
}
