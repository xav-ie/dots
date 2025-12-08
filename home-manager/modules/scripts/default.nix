{ config, ... }:
{
  config = {
    xdg.configFile."scripts/remove_video_silence.py".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/scripts/remove_video_silence.py";
  };
}
