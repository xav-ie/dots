{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  config = {
    # https://github.com/zhaofengli/nix-homebrew/issues/5
    # You must tell nix-darwin to just inherit the same taps as nix-homebrew
    homebrew.taps = builtins.attrNames config.nix-homebrew.taps;

    nix-homebrew = {
      # Install Homebrew under the default prefix
      enable = true;
      # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
      enableRosetta = true;
      # User owning the Homebrew prefix
      user = config.defaultUser;
      # Optional: Declarative tap management
      taps = {
        "homebrew/homebrew-core" = inputs.homebrew-core;
        "homebrew/homebrew-cask" = inputs.homebrew-cask;
        "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      };
      # Optional: Enable fully-declarative tap management
      # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
      mutableTaps = false;
    };

    environment.systemPackages = lib.optionals (config.homebrew.masApps ? "Tailscale") [
      (pkgs.writeShellApplication {
        name = "tailscale";
        meta.description = "create a symlink to the tailscale binary provided by MacOS app";
        text = ''
          /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
        '';
      })
    ];
  };
}
