_: {
  config = {
    programs.mpv.enable = true;
    xdg.mimeApps.defaultApplications = {
      "video/*" = [ "mpv.desktop" ];
    };
    home.sessionVariables = {
      # `ani-cli` now prefers to launch `iina`, but I like `mpv`!
      ANI_CLI_PLAYER = "mpv";
    };
  };
}
