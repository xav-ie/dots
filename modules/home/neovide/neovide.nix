{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      config = {
        xdg.configFile."neovide/config.toml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/neovide/config.toml";
      };
    };
}
