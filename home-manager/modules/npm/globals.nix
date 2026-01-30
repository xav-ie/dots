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
    runtimeInputs = [ config.programs.npm.package ];
    runtimeEnv = {
      NPM_GLOBALS_CONFIG = "${config.dotFilesDir}/home-manager/modules/npm/packages.json";
      NPM_CONFIG_GLOBALCONFIG = ./.npmrc;
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

    home.activation.npmGlobalSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "Syncing npm globals..."
      run ${lib.getExe cfg.package} || true
    '';

    services.scheduled.npm-global-sync = {
      description = "Sync npm global packages";
      command = lib.getExe cfg.package;
      calendar = "daily";
      hour = 9;
      minute = 0;
    };
  };
}
