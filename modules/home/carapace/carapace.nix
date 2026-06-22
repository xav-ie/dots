{
  flake.modules.homeManager.common =
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
        # bd is a cobra binary, so its spec bridges to cobra
        xdg.configFile."carapace/specs/bd.yaml" = lib.mkIf beadsCfg.enable {
          source = config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/carapace/specs/bd.yaml";
        };
      };
    };
}
