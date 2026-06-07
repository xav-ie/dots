{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      config = {
        xdg.configFile."gh-dash/config.yml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/gh-dash/config.yml";
      };
    };
}
