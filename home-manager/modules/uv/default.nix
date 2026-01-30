{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.uv.tools;

  defaultPackage = pkgs.writeNuApplication {
    name = "uv-tool-sync";
    runtimeInputs = [ pkgs.uv ];
    runtimeEnv = {
      UV_TOOLS_CONFIG = "${config.dotFilesDir}/home-manager/modules/uv/packages.json";
    };
    text = builtins.readFile ./sync-uv-tools.nu;
  };
in
{
  options.programs.uv.tools = {
    enable = lib.mkEnableOption "uv tool sync";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The uv-tool-sync package";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.activation.uvToolSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "Syncing uv tools..."
      run ${lib.getExe cfg.package} || true
    '';

    services.scheduled.uv-tool-sync = {
      description = "Sync uv tools";
      command = lib.getExe cfg.package;
      calendar = "daily";
      hour = 9;
      minute = 5;
    };
  };
}
