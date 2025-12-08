{
  pkgs,
  config,
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

      # Source custom files - this allows immediate updates while preserving module functionality
      # (1) env.nu
      extraEnv = ''
        source ${config.dotFilesDir}/home-manager/modules/nushell/env.nu
      '';
      # (2) config.nu
      extraConfig = ''
        source ${config.dotFilesDir}/home-manager/modules/nushell/config.nu
      '';
      # (4) login.nu
      extraLogin = ''
        source ${config.dotFilesDir}/home-manager/modules/nushell/login.nu
      '';
    };
  };
}
