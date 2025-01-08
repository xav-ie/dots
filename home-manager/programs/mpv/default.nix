_: {
  config = {
    programs.mpv.enable = true;
    xdg.mimeApps.defaultApplications = {
      "video/*" = [ "mpv.desktop" ];
    };
  };
}
