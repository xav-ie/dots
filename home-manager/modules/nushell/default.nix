{
  pkgs,
  config,
  lib,
  ...
}:
{
  config = {
    programs.nushell = {
      # latest, please!
      package = pkgs.pkgs-bleeding.nushell;
      enable = true;
      # https://www.nushell.sh/book/configuration.html#configuration-overview
      # (?) -> loading order
      # However, the current "best-practice" recommendation is to set all
      # environment variables (and other configuration) using config.nu and the
      # autoload directories below.
      shellAliases = {
        g = "nvim `+Git | only`";
        gake = "do { git pull; make }";
        gitd = "git d";
        gits = "git s";
        gpw = "gh pr view -w";
        grw = "gh repo view -w";
        gust = "do { git pull; just }";
        info = "info --vi-keys";
        jsut = "just";
        l = "ls -la";
        n = ''nu -e "$env.PATH = ($env.PATH | prepend '${pkgs.nodejs}/bin' | prepend '${pkgs.pnpm}/bin' | prepend '${pkgs.yarn}/bin')"'';
        s = "sudo -E";
        ss = "sudo -E !!";
        tm = "try { tmux attach } catch { tmux }";
        w = "watson";
        zj = "try { zellij attach } catch { zellij }";
      };
      # (3) Files in $nu.vendor-autoload-dirs are loaded. These files can be
      # used for any purpose and are a convenient way to modularize a
      # configuration.
      plugins = with pkgs.pkgs-bleeding; [
        nushellPlugins.gstat
      ];

      # Source custom config file - this allows immediate updates while keeping shellAliases working
      extraConfig = ''
        source ${config.dotFilesDir}/home-manager/modules/nushell/config.nu
      '';
    };

    # Use home.file with mkForce to override env.nu and login.nu only
    # config.nu is handled via extraConfig sourcing to preserve shellAliases
    home.file = {
      # (1) The first file loaded is env.nu, which was historically used to
      # override environment variables.
      "${config.programs.nushell.configDir}/env.nu".source = lib.mkForce (
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/nushell/env.nu"
      );
      # (4) login.nu runs commands or handles configuration that should only
      # take place when Nushell is running as a login shell.
      "${config.programs.nushell.configDir}/login.nu".source = lib.mkForce (
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/nushell/login.nu"
      );
    };
  };
}
