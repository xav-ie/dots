{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.npm.globals;

  defaultPackage = pkgs.writeNuApplication {
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

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The npm-global-sync package";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    services.scheduled.npm-global-sync = {
      description = "Sync npm global packages";
      command = lib.getExe cfg.package;
      calendar = "daily";
      hour = 9;
      minute = 0;
    };
  };
}
