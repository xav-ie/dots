{
  flake.modules.homeManager.common =
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
            g = "nvim -c Neogit -c `silent! bwipeout #`";
            gake = "do { git pull; make }";
            gitd = "git d";
            gits = "git s";
            gust = "do { git pull; just }";
            info = "info --vi-keys";
            jsut = "just";
            l = "ls -la";
            n = ''nu -e "$env.PATH = ($env.PATH | prepend '${pkgs.nodejs}/bin' | prepend '${pkgs.pnpm}/bin' | prepend '${pkgs.yarn}/bin')"'';
            s = "sudo -E";
            ss = "sudo -E !!";
            vnc720 = "hyprctl keyword monitor HDMI-A-2,1280x720@30,auto,0.80";
            vnc1080 = "hyprctl keyword monitor HDMI-A-2,1920x1080@30,auto,1";
            w = "watson";
            zj = "try { zellij attach } catch { zellij }";
          };
          # (3) Files in $nu.vendor-autoload-dirs are loaded. These files can be
          # used for any purpose and are a convenient way to modularize a
          # configuration.
          plugins = [ pkgs.pkgs-mine.nu_plugin_prompt ];

          # Source custom files - this allows immediate updates while preserving module functionality
          # (1) env.nu
          extraEnv = ''
            source ${config.dotFilesDir}/modules/home/nushell/env.nu
          '';
          # (2) config.nu
          extraConfig = ''
            source ${config.dotFilesDir}/modules/home/nushell/config.nu
          '';
          # (4) login.nu
          extraLogin = ''
            source ${config.dotFilesDir}/modules/home/nushell/login.nu
          '';
        };
      };
    };
}
