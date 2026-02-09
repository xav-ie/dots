{
  lib,
  ...
}:
{
  options.programs.orca-slicer = {
    enable = lib.mkEnableOption "OrcaSlicer - 3D model slicer";
  };
}
