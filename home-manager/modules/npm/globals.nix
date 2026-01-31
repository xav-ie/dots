{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.npm.globals;
in
{
  options.programs.npm.globals = {
    enable = lib.mkEnableOption "npm global package sync" // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeNuApplication {
        name = "npm-global-sync";
        runtimeInputs = [ config.programs.npm.package ];
        runtimeEnv = {
          NPM_GLOBALS_CONFIG = "${config.dotFilesDir}/home-manager/modules/npm/packages.json";
          NPM_CONFIG_GLOBALCONFIG = ./.npmrc;
        };
        text = builtins.readFile ./sync-npm-globals.nu;
      };
      defaultText = lib.literalExpression "pkgs.writeNuApplication { ... }";
      description = "The npm-global-sync package";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      exe = "${cfg.package}/bin/npm-global-sync";
    in
    {
      home.packages = [ cfg.package ];

      home.activation.npmGlobalSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        echo "Syncing npm globals (background)..."
        ${exe} &>/dev/null &
        disown
      '';

      services.scheduled.npm-global-sync = {
        description = "Sync npm global packages";
        command = exe;
        calendar = "daily";
        hour = 9;
        minute = 0;
      };
    }
  );
}
