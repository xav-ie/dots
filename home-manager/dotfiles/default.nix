_: {
  config = {
    # There has got to be a better way to do this :(
    home.file.".config/scripts/remove_video_silence.py".source = ./remove_video_silence.py;
    home.file.".config/gh-dash/config.yml".source = ./gh-dash/config.yml;
    home.file.".config/uair/uair.toml".source = ./uair.toml;
    home.file.".config/pijul/config.toml".source = ./pijul/config.toml;
  };
}
