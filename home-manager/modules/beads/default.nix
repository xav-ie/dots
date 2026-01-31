{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.beads;
in
{
  options.programs.beads = {
    enable = lib.mkEnableOption "Beads (bd) - git-backed graph issue tracker for AI agents";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.beads;
      defaultText = lib.literalExpression "pkgs.beads";
      description = "The beads package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
