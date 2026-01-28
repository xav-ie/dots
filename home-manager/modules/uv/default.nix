{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.uv.tools;

  uvToolSync = pkgs.writeNuApplication {
    name = "uv-tool-sync";
    runtimeEnv = {
      UV_TOOLS_CONFIG = "${config.dotFilesDir}/home-manager/modules/uv/packages.json";
    };
    text = builtins.readFile ./sync-uv-tools.nu;
  };
in
{
  options.programs.uv.tools = {
    enable = lib.mkEnableOption "uv tool sync";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ uvToolSync ];

    services.scheduled.uv-tool-sync = {
      description = "Sync uv tools";
      command = "${uvToolSync}/bin/uv-tool-sync";
      calendar = "daily";
      hour = 9;
      minute = 5;
    };
  };
}
