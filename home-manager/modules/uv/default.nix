{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.uv.tools;
in
{
  options.programs.uv.tools = {
    enable = lib.mkEnableOption "uv tool sync";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeNuApplication {
        name = "uv-tool-sync";
        runtimeInputs = [ pkgs.uv ];
        runtimeEnv = {
          UV_TOOLS_CONFIG = "${config.dotFilesDir}/home-manager/modules/uv/packages.json";
        };
        text = builtins.readFile ./sync-uv-tools.nu;
      };
      defaultText = lib.literalExpression "pkgs.writeNuApplication { ... }";
      description = "The uv-tool-sync package";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      exe = "${cfg.package}/bin/uv-tool-sync";
    in
    {
      home.packages = [ cfg.package ];

      home.activation.uvToolSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        echo "Syncing uv tools (background)..."
        ${exe} &>/dev/null &
        disown
      '';

      services.scheduled.uv-tool-sync = {
        description = "Sync uv tools";
        command = exe;
        calendar = "daily";
        hour = 9;
        minute = 5;
      };
    }
  );
}
