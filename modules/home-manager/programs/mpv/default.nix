{ ... }:
{
  xdg.mimeApps.defaultApplications = {
    "video/*" = [ "mpv.desktop" ];
  };
  programs.mpv.enable = true;
}
