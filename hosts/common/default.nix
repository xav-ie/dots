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
      nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
        inherit pkgs;
      };
    };
  };
}
