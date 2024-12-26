{ inputs, pkgs, ... }:
let
  pkgs-bleeding = inputs.nixpkgs-bleeding.legacyPackages.${pkgs.system};
in
{
  config = {
    programs.nushell = {
      # latest, please!
      package = pkgs-bleeding.nushell;
      enable = true;
      # https://www.nushell.sh/book/configuration.html#configuration-overview
      # (?) -> loading order
      # (1) The first file loaded is env.nu, which was historically used to
      # override environment variables.
      envFile.source = ./env.nu;
      # However, the current "best-practice" recommendation is to set all
      # environment variables (and other configuration) using config.nu and the
      # autoload directories below.
      shellAliases = {
        # TODO: move this to a separate file
        # c4 = "COLUMNS=$COLUMNS-4";
        # info = "env info --vi-keys";
        # gake = "git pull; make";
        # gp = "gh pr view";
        # gpw = "gh pr view -w";
        # l = "ls -lah";
        # man = "c4 env man";
        # w = "watson";
        # zj = "zellij attach || zellij";
      };
      # (2) config.nu is typically used to override default Nushell settings,
      # define (or import) custom commands, or run any other startup tasks.
      configFile.source = ./config.nu;
      # (3) Files in $nu.vendor-autoload-dirs are loaded. These files can be used
      # for any purpose and are a convenient way to modularize a configuration.
      plugins = with pkgs-bleeding; [
        nushellPlugins.gstat
      ];
      # (4) login.nu runs commands or handles configuration that should only take
      # place when Nushell is running as a login shell.
      loginFile.source = ./login.nu;
    };
  };
}
