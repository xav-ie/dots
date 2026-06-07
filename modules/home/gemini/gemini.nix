{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.gemini;
    in
    {
      options.programs.gemini = {
        enable = lib.mkEnableOption "Gemini CLI";
        # Add Gemini-specific options here, similar to claude module
      };

      config = lib.mkIf cfg.enable {
        home.file.".gemini/settings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/gemini/settings.json";
      };
    };
}
