{
  flake.modules.homeManager.darwin =
    { config, ... }:
    {
      home.file."Library/Application Support/Claude/claude_desktop_config.json".source =
        config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home-darwin/claude-desktop/claude_desktop_config.json";
    };
}
