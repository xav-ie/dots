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
}
