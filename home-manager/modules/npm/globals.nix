{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.npm.globals;

  npmGlobalSync = pkgs.writeNuApplication {
    name = "npm-global-sync";
    runtimeEnv = {
      NPM_GLOBALS_CONFIG = "${config.dotFilesDir}/home-manager/modules/npm/packages.json";
    };
    text = builtins.readFile ./sync-npm-globals.nu;
  };
in
{
  options.programs.npm.globals = {
    enable = lib.mkEnableOption "npm global package sync" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ npmGlobalSync ];

    services.scheduled.npm-global-sync = {
      description = "Sync npm global packages";
      command = "${npmGlobalSync}/bin/npm-global-sync";
      calendar = "daily";
      hour = 9;
      minute = 0;
    };
  };
}
