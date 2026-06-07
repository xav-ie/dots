{
  flake.modules.homeManager.common =
    { config, ... }:
    {
      config = {
        xdg.configFile."scripts/remove_video_silence.py".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/home/remove-video-silence/remove_video_silence.py";
      };
    };
}
