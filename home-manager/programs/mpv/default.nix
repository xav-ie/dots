{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mpv;
in
{
  options.programs.mpv = {
    settings.enable-webtorrent = lib.mkEnableOption "enable-webtorrent";
  };
  config = {
    home.packages = lib.optional cfg.settings.enable-webtorrent pkgs.pciutils;

    programs.mpv = {
      enable = true;
      package = pkgs.mpv.overrideAttrs (_: {
        scripts =
          with pkgs.mpvScripts;
          [
            autoload # autoloads entries before and after current entry
            mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
            quality-menu # control video quality on the fly
          ]
          # extends mpv to handle magnet URLs
          ++ lib.optional cfg.settings.enable-webtorrent webtorrent-mpv-hook
          ++
            # extends mpv to be controllable with MPD
            lib.optional pkgs.stdenv.isLinux pkgs.mpvScripts.mpris;
      });
      settings.enable-webtorrent = true;
    };
    xdg.mimeApps.defaultApplications = {
      "video/*" = [ "mpv.desktop" ];
    };
    home.sessionVariables = {
      # `ani-cli` now prefers to launch `iina`, but I like `mpv`!
      ANI_CLI_PLAYER = "mpv";
    };
  };
}
