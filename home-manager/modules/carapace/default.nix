{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.carapace;
  beadsCfg = config.programs.beads;
in
{
  config = lib.mkIf cfg.enable {
    # Generate bd.yaml spec when beads is enabled
    xdg.configFile."carapace/specs/bd.yaml" = lib.mkIf beadsCfg.enable {
      source = config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/carapace/specs/bd.yaml";
    };
  };
}
