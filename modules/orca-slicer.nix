# OrcaSlicer 3D slicer `programs.orca-slicer` option, Linux package, macOS cask.
{
  flake.modules.homeManager.common =
    { lib, ... }:
    {
      options.programs.orca-slicer.enable = lib.mkEnableOption "OrcaSlicer - 3D model slicer";
    };

  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf config.programs.orca-slicer.enable {
        home.packages = [ pkgs.orca-slicer ];
      };
    };

  flake.modules.darwin.macos =
    {
      config,
      lib,
      ...
    }:
    let
      hmConfig = config.home-manager.users.${config.defaultUser};
    in
    {
      config = lib.mkIf hmConfig.programs.orca-slicer.enable {
        homebrew.casks = [ "orcaslicer" ];
      };
    };
}
