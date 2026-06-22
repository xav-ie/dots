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
        # bd is a cobra binary, so its spec bridges to cobra; claude is a
        # commander (Node) CLI with no bridge, so it ships a hand-written spec.
        # (--resume is completed natively in nushell, not here — carapace can
        # only show the inserted value, so it can't hide the session id.)
        xdg.configFile."carapace/specs/bd.yaml" = lib.mkIf beadsCfg.enable {
          source = config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/carapace/specs/bd.yaml";
        };
        xdg.configFile."carapace/specs/claude.yaml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/carapace/specs/claude.yaml";
      };
    };
}
