{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      config = {
        home.file.".inputrc".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/inputrc/.inputrc";
      };
    };
}
