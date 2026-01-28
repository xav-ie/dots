{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.defaultUser;
  hmConfig = config.home-manager.users.${user};
  inherit (hmConfig) dotFilesDir;

  uvToolSync = pkgs.writeNuApplication {
    name = "uv-tool-sync-activation";
    runtimeInputs = [ pkgs.uv ];
    runtimeEnv = {
      UV_TOOLS_CONFIG = "${dotFilesDir}/home-manager/modules/uv/packages.json";
    };
    text = builtins.readFile ../../home-manager/modules/uv/sync-uv-tools.nu;
  };

  npmGlobalSync = pkgs.writeNuApplication {
    name = "npm-global-sync-activation";
    runtimeInputs = [ pkgs.nodejs ];
    runtimeEnv = {
      NPM_GLOBALS_CONFIG = "${dotFilesDir}/home-manager/modules/npm/packages.json";
    };
    text = builtins.readFile ../../home-manager/modules/npm/sync-npm-globals.nu;
  };
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Syncing uv tools..."
    su - ${user} -c "${lib.getExe uvToolSync}" || true

    echo "Syncing npm globals..."
    su - ${user} -c "${lib.getExe npmGlobalSync}" || true
  '';
}
