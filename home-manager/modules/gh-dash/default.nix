{ config, ... }:
{
  config = {
    xdg.configFile."gh-dash/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/gh-dash/config.yml";
  };
}
