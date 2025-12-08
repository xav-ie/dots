{ config, ... }:
{
  config = {
    xdg.configFile."pijul/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/pijul/config.toml";
  };
}
