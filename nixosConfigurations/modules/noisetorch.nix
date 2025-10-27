{
  config,
  lib,
  pkgs,
  ...
}:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  noisetorchInPackages = builtins.elem pkgs.noisetorch (hmConfig.home.packages or [ ]);
in
{
  config = lib.mkIf noisetorchInPackages {
    # Noisetorch requires CAP_SYS_RESOURCE capability to adjust audio realtime priorities
    security.wrappers.noisetorch = {
      owner = "root";
      group = "root";
      source = lib.getExe pkgs.noisetorch;
      capabilities = "cap_sys_resource+ep";
    };
  };
}
