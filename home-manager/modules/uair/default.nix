{ config, ... }:
{
  config = {
    xdg.configFile."uair/uair.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/uair/uair.toml";
  };
}
