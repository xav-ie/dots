{ config, ... }:
{
  config = {
    home.file.".inputrc".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/inputrc/.inputrc";
  };
}
