{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.worktrunk;
in
{
  options.programs.worktrunk = {
    enable = lib.mkEnableOption "worktrunk (wt) - git worktree management for parallel AI agent workflows";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pkgs-bleeding.worktrunk;
      defaultText = lib.literalExpression "pkgs.pkgs-bleeding.worktrunk";
      description = "The worktrunk package to use";
    };

    enableNushellIntegration = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.nushell.enable;
      defaultText = lib.literalExpression "config.programs.nushell.enable";
      description = "Whether to enable nushell integration (wrapper function + completions)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.nushell.extraConfig = lib.mkIf cfg.enableNushellIntegration ''
      source ${
        pkgs.runCommand "worktrunk-nushell-integration.nu" { } ''
          ${cfg.package}/bin/wt config shell init nu > "$out"
        ''
      }
    '';
  };
}
