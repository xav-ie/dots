{
  flake.modules.homeManager.common =
    { config, pkgs, ... }:
    {
      config = {
        home.packages = [ pkgs.uair ];
        xdg.configFile."uair/uair.toml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/uair/uair.toml";
      };
    };
}
