{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      config = {
        xdg.configFile."pijul/config.toml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/pijul/config.toml";
      };
    };
}
