{ config, ... }:
{
  config = {
    xdg.configFile."neovide/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/neovide/config.toml";
  };
}
