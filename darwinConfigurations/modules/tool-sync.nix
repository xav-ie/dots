{
  config,
  lib,
  ...
}:
let
  user = config.defaultUser;
  hmConfig = config.home-manager.users.${user};
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Syncing uv tools..."
    su - ${user} -c "${lib.getExe hmConfig.programs.uv.tools.package}" || true

    echo "Syncing npm globals..."
    su - ${user} -c "${lib.getExe hmConfig.programs.npm.globals.package}" || true

    echo "Syncing claude plugins..."
    su - ${user} -c "${lib.getExe hmConfig.programs.claude.pluginSyncPackage}" || true
  '';
}
